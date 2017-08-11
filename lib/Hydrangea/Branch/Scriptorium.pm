package Hydrangea::Branch::Scriptorium;

use strictures 2;
use Hydrangea::Future;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;
use Moo;

#has script_directory => (is => 'ro', required => 1);

has loop => (is => 'ro', required => 1);

has stream => (is => 'ro', required => 1);

has in_flight => (is => 'ro', default => sub { {} });

has tx_gen => (is => 'ro', default => 'A0001');

sub start_tx {
  my ($self, @start) = @_;
  my $id = ++$self->{tx_gen};
  $self->stream->write_message(
    [ tx => $id ], @start
  );
  return $self->in_flight->{$id} = Hydrangea::Future->new;
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
    my $f = $self->start_tx(connection => register => [ qw(branch foo) ]);
    $f->on_done(sub { warn "registered" });
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
      } elsif ($message[0] eq 'bye') {
        await $trunk->write_message_and_close(qw(k bye));
        return;
      } elsif {
        die "Eeep";
      }
    }
  };
}

1;
