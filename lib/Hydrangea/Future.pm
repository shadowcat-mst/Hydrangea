package Hydrangea::Future;

use strictures 2;
use base qw(Future);

sub accepts {
  my ($self, $cmd) = @_;
  return 1 if $cmd eq 'done' or $cmd eq 'fail';
  return 0;
}

1;
