package Hydrangea::Trunk::MessageBus;

use strictures 2;
use Hydrangea::Trunk::Conversation;
use Moo;

has roots => (is => 'ro', default => sub { {} });

has commands => (is => 'ro', default => sub { {} });

has conversations => (is => 'ro', default => sub { {} });

has transactions => (is => 'ro', default => sub { {} });

has id_gen => (is => 'ro', default => 'A0000');

sub handle_root_message {
  my ($self, $from, @message) = @_;
  if ($message[0] eq 'message') {
    my $ident = join "\0", @$from;
    if (my $conv = $self->conversations->{$ident}) {
      $conv->handle_root_message($from, @message[1..$#message]);
    } elsif (
      my ($cmd_name, $start_msg) = $message[1] =~ /\A(\w+)(?:\s+(.*))?\Z/
    ) {
      if (my $cmd_spec = $self->commands->{$cmd_name}) {
        $self->start_conversation($ident, $cmd_spec, $from, $start_msg);
      }
    }
  }
}

sub handle_branch_message {
  my ($self, $from, @message) = @_;
  if ($message[0] eq 'tx') {
    my (undef, $txid, @rest) = @message;
    if (my $conv = $self->transactions->{$txid}) {
      $conv->handle_branch_message($from, @rest);
    }
  }
}

sub relay_branch_message {
  my ($self, $from, @message) = @_;
  my $root = $self->roots;
  $root = $root->{shift(@message)} while ref($root) eq 'HASH';
  if ($root) {
    $root->write_message([ 'bus' ] => @message);
  }
}

sub conversation_finished {
  my $conv = delete $_[0]->conversations->{$_[1]};
  delete $_[0]->transactions->{$conv->trunk_tx_id};
}

sub start_conversation {
  my ($self, $ident, $cmd_spec, $with, $start_msg) = @_;
  my $id = ++$self->{id_gen};
  my $conv = Hydrangea::Trunk::Conversation->new(
    trunk_tx_id => $id,
    cmd_spec => $cmd_spec,
    requestor => $with,
    bus => $self,
  )->start($start_msg);
  $self->conversations->{$ident} = $conv;
  $self->transactions->{$id} = $conv;
}

1;
