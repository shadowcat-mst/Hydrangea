package Hydrangea::Root::IRC;

use strictures 2;
use Net::Async::IRC;
use curry;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;
use Moo;

has loop => (is => 'ro', required => 1);

has stream => (is => 'ro', required => 1);

has client => (is => 'lazy', builder => sub {
  Net::Async::IRC->new
});

has nick => (is => 'ro', required => 1);

has host => (is => 'ro', required => 1);

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
    $trunk->write_message(
      [ 'registration' ],
      connection => register => [ qw(root irc), $self->host, $self->nick ]
    );
    $self->stream->configure(
      on_message => $self->curry::weak::handle_trunk_message,
    );
    while (1) {
      my $client = $self->client;
      $self->loop->add($client);
      warn "connecting";
      $client->configure(
        on_closed => (my $closed_f = Future->new)->curry::done
      );
      await $client->login(
        nick => $self->nick,
        host => $self->host,
      );
      warn "connected";
      await $closed_f;
      warn "disconnected";
      await $self->loop->delay_future(after => 15);
    }
  }
}

sub handle_irc_privmsg {
  my ($self, undef, $message, $hints) = @_;
  $self->stream->write_message(
    [ $hints->{prefix_nick} ], bus => message => $hints->{text}
  );
}

sub handle_trunk_message {
  my ($self, $from, $cmd, @message) = @_;
  if ($cmd eq 'registration') {
    if ($message[0] eq 'done') {
      $self->client->configure(
        on_message_PRIVMSG => $self->curry::weak::handle_irc_privmsg
      );
    }
  }
  if ($cmd eq 'message') {
    my ($to, $text) = @message;
    $self->client->do_PRIVMSG(
      target => $to,
      text => $text,
    );
  }
}

1;
