package Hydrangea::JSONStream;

use strictures 2;
use JSON::MaybeXS;
use base qw(IO::Async::Stream);
use Future;

sub on_read {
  my ($self, $buffref, $eof) = @_;
  if (my $code = $self->{on_message}) {
    while( $$buffref =~ s/^(.*\n)// ) {
      my $line = $1;
      chomp($line);
      $code->(@{decode_json($line)});
    }
  }
  return 0;
}

sub configure {
  my ($self, %args) = @_;
  if (exists $args{on_message}) {
    $self->{on_message} = delete $args{on_message};
  }
  $self->SUPER::configure(%args);
}

sub read_message {
  my ($self) = @_;
  $self->read_until("\n")->then(sub {
    my ($line, $eof) = @_;
    return Future->done if $eof;
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
