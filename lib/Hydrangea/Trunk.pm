package Hydrangea::Trunk;

use strictures 2;
use Hydrangea::JSONStream;
use Hydrangea::Trunk::MessageBus;
use curry;
use PerlX::AsyncAwait::Runtime;
use PerlX::AsyncAwait::Compiler;
use Moo;

has listener => (is => 'ro', required => 1);

has loop => (is => 'ro', required => 1);

has bus => (is => 'lazy', builder => sub {
  Hydrangea::Trunk::MessageBus->new
});

has root_connections => (is => 'ro', default => sub { {} });

has branch_connections => (is => 'ro', default => sub { {} });

sub run {
  my ($self) = @_;
  $self->listener->configure(
    handle_class => 'Hydrangea::JSONStream',
    on_accept => $self->curry::weak::accept_connection,
  );
  return Future->new->on_ready(sub { undef $self });
}

sub accept_connection {
  my ($self, undef, $stream) = @_;
  $self->loop->add($stream);
  $self->listener->adopt_future(async_do {
    my @offer = await $stream->read_message;
    unless (
      @offer == 3
      and $offer[0] eq 'protocol'
      and $offer[1] eq 'offer'
      and $offer[2] eq 'v1'
    ) {
      await $stream->write_message_and_close(protocol => 'negotiation_failure');
      return;
    }
    $stream->write_message(protocol => accept => 'v1');
    my @reg = await $stream->read_message;
    unless (
      @reg == 4
      and $reg[1] eq 'connection'
      and $reg[2] eq 'register'
    ) {
      await $stream->write_message_and_close(protocol => 'botch');
      return;
    }
    my ($type, @path) = @{$reg[3]};
    unless ($self->can("setup_${type}_connection")) {
      await $stream->write_message_and_close(
        [ 'connection' ], @{$reg[0]}, 'fail'
      );
      return;
    }
    $stream->configure(on_closed => (my $closed_f = Future->new)->curry::done);
    $self->${\"setup_${type}_connection"}($stream, $closed_f, @path);
    $stream->write_message(["connection"],@{$reg[0]},'done');
    return $closed_f;
  }->else(sub { warn "Boom"; Future->done }));
}

sub setup_root_connection {
  my ($self, $stream, $closed_f, @path) = @_;
  my $ident = join("\0", @path);
  $self->root_connections->{$ident} = $stream;
  my @walk = @path; my $last = pop @walk;
  my $roots_targ = $self->bus->roots;
  $roots_targ = $roots_targ->{$_}||={} for @walk;
  $roots_targ->{$last} = $stream;
  $closed_f->on_done(sub {
    delete $self->root_connections->{$ident};
    my $roots_targ = $self->bus->roots;
    $roots_targ = $roots_targ->{$_} for @walk;
    delete $roots_targ->{$last};
  });
  $stream->configure(
    on_message => $self->curry::weak::handle_root_message(\@path),
  );
}

sub handle_root_message {
  my ($self, $path, $from, @message) = @_;
  return unless shift(@message) eq 'bus'; # no other messages yet
  $self->bus->handle_root_message(
    [ @$path, @$from ], @message
  );
}

sub setup_branch_connection {
  my ($self, $stream, $closed_f, $name) = @_;
  $self->branch_connections->{$name} = [ $stream ];
  $closed_f->on_done(sub {
    my @old = @{(delete $self->branch_connections->{$name})->[1]||[]};
    delete @{$self->bus->commands}{@old};
  });
  $stream->configure(
    on_message => $self->curry::weak::handle_branch_message($stream, $name),
  );
}

sub handle_branch_message {
  my ($self, $branch, $name, $from, @message) = @_;
  if ($message[0] eq 'connection') {
    if ($message[1] eq 'commands') {
      my @old = @{$self->branch_connections->{$name}[1]||[]};
      delete @{$self->bus->commands}{@old};
      my @commands = @{$message[2]};
      @{$self->bus->commands}{@commands}
        = map +{ name => $_, branch => $branch }, @commands;
      $self->branch_connections->{$name}[1] = \@commands;
      $branch->write_message(['connection'],@$from,'done');
    }
  }
  $self->bus->handle_branch_message(
    [ $name, @$from ], @message
  );
}

1;
