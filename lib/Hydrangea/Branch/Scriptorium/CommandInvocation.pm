package Hydrangea::Branch::Scriptorium::CommandInvocation;

use strictures 2;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;
use IO::Async::Process;
use Object::Tap;
use curry;
use Moo;

has id => (is => 'ro', required => 1);

has requestor => (is => 'ro', required => 1);

has stream => (is => 'ro', required => 1);

has loop => (is => 'ro', required => 1);

has command => (is => 'ro', required => 1);

has exit_future => (is => 'lazy', builder => sub {
  Future->new;
});

has process => (is => 'lazy', builder => sub {
  my ($self) = @_;
  IO::Async::Process->new(
    command => $self->command,
    stdin => { via => 'pipe_write' },
    stdout => { via => 'pipe_read' },
    on_finish => $self->exit_future->curry::done,
  )->$_tap(sub { $_[0]->stdout->configure(on_read => sub { 0 }) });
});

sub accepts {
  return $_[1] eq 'message';
}

sub message {
  my ($self, $message) = @_;
  $self->process->stdin->write($message."\n");
}

sub run {
  my ($self) = @_;
  $self->loop->add($self->process);
  $self->tell_requestor('started');
  return async_do {
    my $ef = $self->exit_future;
    my $proc_out = $self->process->stdout;
    my $lf;
    while (1) {
      await (Future->needs_any(
        $ef->without_cancel,
        $lf = $proc_out->read_until("\n")
      ));
      if ($ef->is_ready or $lf->is_ready and ($lf->get)[1]) {
        $self->tell_requestor("done");
        return;
      }
      my $line = $lf->get;
      chomp($line);
      $self->tell_requestor(message => $line);
    }
  };
}

sub tell_requestor {
  my ($self, @message) = @_;
  $self->stream->write_message(
    [ tx => $self->id ], @{$self->requestor}, @message
  );
}

1;
