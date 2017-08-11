package Hydrangea::Root::IRC;

use strictures 2;
use Net::Async::IRC;
use curry;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;
use Moo;

has loop => (is => 'ro', required => 1);

#has stream => (is => 'ro', required => 1);

has client => (is => 'lazy', builder => sub {
  my ($self) = @_;
  Net::Async::IRC->new(
    on_message_PRIVMSG => $self->curry::weak::handle_privmsg
  );
});

has nick => (is => 'ro', required => 1);

has host => (is => 'ro', required => 1);

sub run {
  my ($self) = @_;
  return async_do {
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

1;
