package Hydrangea::Trunk::Conversation;

use strictures 2;
use Moo;

has trunk_tx_id => (is => 'ro', required => 1);

has cmd_spec => (is => 'ro', required => 1);

has branch => (is => 'lazy', builder => sub {
  shift->cmd_spec->{branch}
});

has requestor => (is => 'ro', required => 1);

has bus => (is => 'ro', required => 1, weak_ref => 1);

has branch_tx => (is => 'rw');

sub start {
  my ($self, $start_msg) = @_;
  $self->branch->write_message(
    [ tx => $self->trunk_tx_id ], run => $self->cmd_spec->{name}, $start_msg
  );
  return $self;
}

sub handle_root_message {
  my ($self, $from, $message) = @_;
  $self->branch->write_message(
    [ tx => $self->trunk_tx_id ], @{$self->branch_tx}, message => $message
  );
}

sub handle_branch_message {
  my ($self, $from, $cmd, $message) = @_;
  if ($cmd eq 'started') {
    $self->branch_tx($from);
  } elsif ($cmd eq 'message') {
    $self->bus->relay_branch_message(
      $from, @{$self->requestor}, $cmd, $message
    );
  } elsif ($cmd eq 'done') {
    $self->bus->conversation_finished(join("\0", @{$self->requestor}));
  }
}

1;
