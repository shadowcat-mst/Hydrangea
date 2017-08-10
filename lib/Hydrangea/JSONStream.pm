package Hydrangea::JSONStream;

use strictures 2;
use JSON::MaybeXS;
use base qw(IO::Async::Stream);
use Future;

sub on_read { 0 }

sub read_message {
  my ($self) = @_;
  $self->read_until("\n")->then(sub {
    my ($line) = @_;
    chomp($line);
    return Future->done(@{decode_json($line)});
  });
}

sub write_message {
  my ($self, @message) = @_;
  $self->write(encode_json(\@message)."\n");
}

sub write_message_and_close {
  my ($self, @message) = @_;
  $self->write_message(@message)
       ->then(sub { $self->close; return Future->done });
}

1;
