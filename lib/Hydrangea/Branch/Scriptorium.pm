package Hydrangea::Branch::Scriptorium;

use strictures 2;
use Moo;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;

#has script_directory => (is => 'ro', required => 1);

has trunk_stream => (is => 'ro', required => 1);

sub run {
  my ($self) = @_;
  my $trunk = $self->trunk_stream;
  return async_do {
    while (my @message = await $trunk->read_message) {
      if (@message and $message[0] eq 'bye') {
        await $trunk->write_message_and_close(qw(k bye));
        return;
      }
      await $trunk->write_message('ack');
    }
  };
}

1;
