package CGI::Application::Plugin::AutoRunmode;

use strict;
use attributes;
require Exporter;

our @ISA = qw(Exporter);

# always export the attribute handlers
sub import{
		__PACKAGE__->export_to_level(1, @_, qw[
		 	MODIFY_CODE_ATTRIBUTES
			FETCH_CODE_ATTRIBUTES
		 ]
		 );
};

our @EXPORT_OK = qw[
		cgiapp_prerun
		MODIFY_CODE_ATTRIBUTES
		FETCH_CODE_ATTRIBUTES
	];

our $VERSION = '0.05';

our %__illegal_names = qw[ 
	can can
	isa isa
	VERSION VERSION
	AUTOLOAD AUTOLOAD
	new	new
	DESTROY DESTROY
];

sub cgiapp_prerun{
	my ($self, $rm) = @_;	
	my %rmodes = ($self->run_modes());
	# If prerun_mode has been set, use it!
	my $prerun_mode = $self->prerun_mode();
	if (length($prerun_mode)) {
		$rm = $prerun_mode;
	}
	
	unless (exists $rmodes{$rm}){
		# security check: disallow non-word characters 
		unless ($rm =~ /\W/){
		
			# check :Runmodes
			my $sub = $self->can($rm);
			if ($sub){;
				my @attribs =  attributes::get($sub);
				foreach (@attribs){
					$self->run_modes( $rm => $rm), return
						if $_ eq 'Runmode';
				}
			}
		
			# check delegate
			my $delegate = $self->param('::Plugin::AutoRunmode::delegate');
			if ($delegate and not exists $__illegal_names{$rm}){
				$sub = $delegate->can($rm);
				if ($sub){
					# construct a closure, as we need a second
					# parameter (the delegate)
					my $closure = sub { $sub->($_[0], $delegate); };
					$self->run_modes( $rm => $closure);
				}
			}
		}
	}
}

sub install{
	my ($package, $app) = @_;
	$app->add_callback('prerun', \&cgiapp_prerun, 'LAST');
}


sub MODIFY_CODE_ATTRIBUTES{
	my ($pkg, $ref, @attr) = @_;
	my @unknown;
	foreach (@attr){
		$CGI::Application::Plugin::AutoRunmode::RUNMODES{"$ref"} = 1, next
			if $_ eq 'Runmode';
		push @unknown, $_;
	}
	return @unknown;
}

sub FETCH_CODE_ATTRIBUTES{
	my ($pkg, $sub) = @_;
	$sub = $CGI::Application::Plugin::AutoRunmode::RUNMODES{"$sub"};
	return $sub ? ('Runmode') : (); 
}


1;
__END__

=head1 NAME

CGI::Application::Plugin::AutoRunmode - CGI::App plugin to automatically register runmodes

=head1 SYNOPSIS

Using subroutine attributes:

	package MyApp;
	use base 'CGI::Application';
	use CGI::Application::Plugin::AutoRunmode 
		qw [ cgiapp_prerun];
	
	sub my_run_mode : Runmode {
		# do something here
	}
	
	sub another_run_mode : Runmode {
		# do something else
	}
	
	# you now have two run modes
	# "my_run_mode" and "another_run_mode"


Using a delegate object

  	package MyAppRunmodes;
	# the delegate class
		sub my_run_mode  {
			my ($app, $delegate) = @_;
				# do something here
		}
	    
		sub another_run_mode  {
				# do something else
		}
		
	package MyApp;
   	use base 'CGI::Application';
	use CGI::Application::Plugin::AutoRunmode 
		qw [ cgiapp_prerun];
	   
		sub setup{
			my ($self) = @_;
			my $delegate = 'MyAppRunmodes';
				# $delegate can be a class name or an object
			$self->param('::Plugin::AutoRunmode::delegate' => $delegate);
		}
	
	 # you now have two run modes
	 # "my_run_mode" and "another_run_mode"

=head1 DESCRIPTION

This plugin for CGI::Application provides easy
ways to setup run modes. You can just write
the methods that implement a run mode, you do
not have to explicitly register it with CGI::App anymore.

There are two approaches: You can flag methods
in your CGI::App subclass with the attribute "Runmode",
or you can assign a delegate object, all whose methods
will become runmodes (you can also mix both approaches).

Delegate runmodes receive two parameters: The first one
is the CGI::App instance, followed by the delegate instance
or class name. This can be useful if you have delegate objects
that contain state.

It both cases, the resulting runmodes will have the same
name as the subroutine that implements them, and you can
use the  cgiapp_prerun method provided by this plugin to
activate them.


=head2 EXPORT

The module can export a cgiapp_prerun,
which you should import unless you already
have such a method.

	use CGI::Application::Plugin::AutoRunmode 
		qw [ cgiapp_prerun];

If you already have a cgiapp_prerun, you have to
invoke the plugin's code from within your method:

	# if you already have your own cgiapp_prerun
	# do this:
	use CGI::Application::Plugin::AutoRunmode;
	
	sub cgiapp_prerun{
		CGI::Application::Plugin::AutoRunmode::cgiapp_prerun(@_);
		# your code goes here
	}

Even if you do not import cgiapp_prerun from the plugin,
make sure you still have the default imports, which are
necessary to enable the Runmode attribute.
Unless you are not using these attributes (because you like
the delegate object approach more), you must do

	use CGI::Application::Plugin::AutoRunmode;

and not

	use CGI::Application::Plugin::AutoRunmode ();
		# this will disable the Runmode attributes


=head3 using the callback interface

You can also use the new callback interface of CGI::Application::Callbacks.
By calling the install method, this plugin will install itself
as a callback in the LAST position of the PRERUN phase.
This setup enables you to provide additional prerun modes,
and you can also change the runmode from within these prerun modes.

	package MyApp;
	use base 'CGI::Application::Callbacks';
	use CGI::Application::Plugin::AutoRunmode;
	
	sub setup{
		my $self = shift;
		install CGI::Application::Plugin::AutoRunmode($self);
	}
	
	sub do_something : Runmode{
		# ....
	}

=head2 How does it work?

After CGI::App has determined the name of the
run mode to be executed in the normal way, 
cgiapp_prerun checks if such a run mode exists
in the map configured by $self->run_modes().

If the run mode already exists, it gets executed
normally (this module does nothing). This means
that you can mix the ways to declare run modes
offered by this plugin with the style provided 
by core CGI::App.

If that is not the case, it tries to find a method
of the same name
in the application class (or its superclasses)
that has been flagged as a Runmode.
If it finds one, it augments the mapping with
a subroutine reference to that method.

If that step fails, it looks if a delegate has been
defined and searches the methods of that delegate
object for one that matches the name of the runmode.

The runmode can then be executed by CGI::App
as if it had been set up by $self->run_modes()
in the first place.


=head2 A word on security

The whole idea of this module (to reduce code complexity
by automatically mapping a URL
to a subroutine that gets executed) is a potential 
security hazard and great care has to be 
taken so that a remote user cannot run 
code that you did not intend them to.

In order to prevent a carefully crafted URL to access
code in other packages, this module disallows non-word
characters (such as : )  in run mode names.

Also, you have to make sure that when using a delegate
object, that it (and its superclasses) only contain
run modes (and no other subroutines).

The following run mode names are disallowed
by this module:

	can isa VERSION AUTOLOAD new DESTROY


=head1 SEE ALSO

=over

=item *

L<CGI::Application::Plugin::AutoRunmode::FileDelegate>

=item *

L<CGI::Application>

=item *

The CGI::App wiki at 
L<http://twiki.med.yale.edu/twiki2/bin/view/CGIapp/WebHome>.

=back

=head1 AUTHOR

Thilo Planz, E<lt>thilo@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2004/05 by Thilo Planz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
