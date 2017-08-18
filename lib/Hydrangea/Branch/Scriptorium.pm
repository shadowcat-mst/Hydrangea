package Hydrangea::Branch::Scriptorium;

use strictures 2;
use Hydrangea::Future;
use Hydrangea::Branch::Scriptorium::CommandInvocation;
use Text::ParseWords qw(shellwords);
use JSON::MaybeXS;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;
use Path::Tiny;
use Moo;

has script_directory => (is => 'ro', required => 1);

has loop => (is => 'ro', required => 1);

has stream => (is => 'ro', required => 1);

has in_flight => (is => 'ro', default => sub { {} });

has tx_gen => (is => 'ro', default => 'A0000');

has commands => (is => 'lazy', builder => sub {
  my ($self) = @_;
  my @commands = grep $_->is_file, path($self->script_directory)->children;
  return +{
    map +($_->basename, [ "$_" ]), @commands,
  }
});

sub start_tx {
  my ($self, @start) = @_;
  my $id = ++$self->{tx_gen};
  $self->stream->write_message(
    [ tx => $id ], @start
  );
  return $self->in_flight->{$id}
    = Hydrangea::Future->new->on_ready(sub { delete $self->in_flight->{$id} });
}

sub start_command {
  my ($self, $from, $cmd, $arg) = @_;
  my @argv = shellwords($arg);
  my $id = ++$self->{tx_gen};
  my $ci = Hydrangea::Branch::Scriptorium::CommandInvocation->new(
    id => $id,
    requestor => $from,
    command => [ $cmd, @argv ],
    stream => $self->stream,
    loop => $self->loop,
  );
  $self->stream->adopt_future(
    $ci->run->on_ready(sub { delete $self->in_flight->{$id} })
  );
  return $self->in_flight->{$id} = $ci;
}

sub run {
  my ($self) = @_;
  my $trunk = $self->stream;
  return async_do {
    $trunk->write_message(protocol => offer => 'v1');
    my @reply = await $trunk->read_message;
    unless (
      @reply == 3
      and $reply[0] eq 'protocol'
      and $reply[1] eq 'accept'
      and $reply[2] eq 'v1'
    ) {
      await $trunk->write_message_and_close(protocol => 'negotiation_failure');
      return;
    }
    my $f = $self->start_tx(connection => register => [ qw(branch foo) ])
                 ->then($self->curry::register_commands);
    while (my ($from, @message) = await $trunk->read_message) {
      if ($message[0] eq 'tx') {
        my $targ = $self->in_flight->{$message[1]};
        my (undef, undef, $cmd, @args) = @message;
        if ($targ->accepts($cmd)) {
          $targ->$cmd(@args);
        } else {
          await $trunk->write_message_and_close(error => 'unacceptable');
          return;
        }
      } elsif ($message[0] eq 'run') {
        if (my $cmd = $self->commands->{$message[1]}) {
          $self->start_command($from, @$cmd, $message[2]);
        } else {
          await $trunk->write_message_and_close(error => 'unacceptable');
          return;
        }
      } elsif ($message[0] eq 'bye') {
        await $trunk->write_message_and_close(qw(k bye));
        return;
      } else {
        warn "Unhandled (trunk): ".encode_json(\@message);
      }
    }
  };
}

sub register_commands {
  my ($self) = @_;
  $self->start_tx(connection => commands => [ keys %{$self->commands} ]);
}

1;
