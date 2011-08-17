package On::Event;
{
  $On::Event::VERSION = 'v0.1.0';
}
# ABSTRACT: Flexible event handling over the power of AnyEvent

use strict;
use warnings;
use Any::Moose 'Role';

has 'autoload' => (isa=>'Bool', is=>'rw', default=>1);
has '_listeners' => (isa=>'HashRef', is=>'ro', default=>sub{{}});

sub import {
    my( $pkg ) = caller;
    if ( @_ > 1 ) {
        my $class = "On::Event::$_[1]"; ;
        eval qq{ require $class; }; ## no critic (ProhibitStringyEval)
        Carp::croak $@ if $@;
        eval qq{ package $pkg; \$class->import(\@_[2..$#_]); };## no critic (ProhibitStringyEval)
        Carp::croak $@ if $@;
    }
    no strict 'refs'; ## no critic (ProhibitNoStrict)
    unless (exists ${"$pkg\::"}{"_valid_events"}) {
        *{$pkg."::_valid_events"} = {};
        *{$pkg."::has_event"} = \&has_event;
        *{$pkg."::has_events"} = \&has_event;
    }
}


sub unimport {
    my( $pkg ) = caller;
    no strict 'refs'; ## no critic (ProhibitNoStrict)
    delete ${$pkg."::"}{"has_event"};
    delete ${$pkg."::"}{"has_events"};
}


sub has_event(@) { ## no critic (ProhibitSubroutinePrototypes)
    my( $pkg ) = caller;
    my $valid = do {
        no strict 'refs'; ## no critic (ProhibitNoStrict)
        \%{$pkg."::_valid_events"};
        };
    $valid->{$_}=1 for @_; ## no critic (ProhibitAccessOfPrivateData)
}


sub event_exists {
    my $self = shift;
    my( $event ) = @_;
    no strict 'refs'; ## no critic (ProhibitNoStrict)
    return exists ${ref($self)."::_valid_events"}{$event};
}


sub on {
    my $self = shift;
    my( $event, $listener ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    $self->{_listeners}{$event} //= [];
    push @{ $self->{_listeners}{$event} }, $listener;
    return $listener;
}


sub trigger {
    no warnings 'redefine';
    if ( defined *Coro::async{CODE} ) {
        *trigger = \&trigger_coro;
        goto \&trigger_coro;
    }
    else {
        *trigger = \&trigger_stock;
        goto \&trigger_stock;
    }
}


sub trigger_stock {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    foreach ( @{ $self->{_listeners}{$event} } ) {
        $_->(@args);
    }
    return;
}


sub trigger_coro {
    my $self = shift;
    my( $event, @args ) = @_;
    if ( ! $self->event_exists($event) ) {
        die "Event $event does not exist";
    }
    return unless exists $self->{_listeners}{$event};
    foreach ( @{ $self->{_listeners}{$event} } ) {
        &Coro::async( $_, @args );
    }
    Coro::cede();
    return;
}




sub remove_all_listeners {
    my $self = shift;
    my( $event ) = @_;
    delete $self->{_listeners}{$event};
}



no Any::Moose;
1;

__END__
=pod

=head1 NAME

On::Event - Flexible event handling over the power of AnyEvent

=head1 VERSION

version v0.1.0

=head1 SYNOPSIS

  package Example;
  use Any::Moose;
  use On::Event;
  with 'On::Event';
  has_event 'ping';
  
  package main;
  my $example = Example->new;
  $example->on( ping => sub { say "Got a ping!" } );
  $example->on( ping => sub { say "Got another ping!" } );
  $example->trigger( "ping" ); # prints "Got a ping!" and "Got another ping!"
  $example->remove_all_listeners( 'ping' );

=head1 DESCRIPTION

This provides a simple and flexible event API, implemented on top of
AnyEvent.  The API is in the style of Node.js.

=for test_synopsis use v5.10;

=head1 USING

On::Event is implemented as a Moose Role.  To add events to your object:

  with 'On::Event';

It provides a helper declare what events your object supports:

  use On::Event;
  
  has_event 'event_name';
  has_events qw( event1 event2 event3 );

Users of your class can now call the "on" method in order to register an event handler:

  $obj->on( event1 => sub { say "I has an event;" } );

And clear their event listeners with:

  $obj->remove_all_listeners( 'ping' );

You can trigger events from your class with the "trigger" method:

  $self->trigger( "event1", "arg1", "arg2", "argn" );

You can remove the has_event and has_events helpers by unimporting On::Event:

  no On::Event;

=begin internal

=over

=item our sub unimport

This is used to clean up the functions we insert into the caller's namespace.

=back

=end internal

=head1 HELPERS (exported subroutines)

=over

=item sub has_event( Array[Str] *@event_names ) is export

=item sub has_events( Array[Str] *@event_names ) is export

Registers your class as being able to trigger the event names listed.

=back

=head1 METHODS

=over

=item our method event_exists( Str $event ) returns Bool

Returns true if $event is a valid event name for this class.

=item our method on( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is triggered ALL
registered listeners are executed.

Returns the listener coderef.

=item our method trigger( Str $event, Array[Any] *@args )

Normally called within the class using the On::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using coroutines then each listener will get its own thread and
trigger will cede before returning.

=begin internal

=item my method trigger_stock( Str $event, Array[Any] *@args )

The standard impelementation of the trigger method-- calls the listeners
immediately and in the order they were defined.


=end internal

=begin internal

=item my method trigger_coro( Str $event, Array[Any] *@args )

The L<Coro> implementation of the trigger method-- calls each of the listeners
in its own thread and triggers immediate execution by calling cede before
returning.


=end internal

=item our method remove_all_listeners( Str $event )

Removes all listeners for $event

=back

=head1 AUTHOR

Becca <becca@referencethis.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Rebecca Turner.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
