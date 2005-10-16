package CGI::Application::Plugin::AutoRunmode;

use strict;
require Exporter;
require CGI::Application;
use Carp;

our $VERSION = '0.10';


our %RUNMODES = ();

# two different versions of this module,
# depending on whether Attribute::Handlers is
# available

my $has_ah;
BEGIN{
	eval 'use Attribute::Handlers; $has_ah=1;'
}

if ($has_ah){
	$has_ah = eval <<'WITH_AH';

sub CGI::Application::Runmode :ATTR(CODE) {
	my ( $pkg, $glob, $ref, $attr, $data, $phase ) = @_;
	no strict 'refs';
	$RUNMODES{"$ref"} = 1;
}
sub CGI::Application::StartRunmode :ATTR(CODE) {
	my ( $pkg, $glob, $ref, $attr, $data, $phase ) = @_;
	install_start_mode($pkg, $ref);
}

# the Attribute::Handler version still exports a MODIFY_CODE_ATTRIBUTES
# but only to provide backwards compatibility (case-independent attribute
# names )

sub MODIFY_CODE_ATTRIBUTES{
	my ($pkg, $ref, @attr) = @_;
	foreach (@attr){
		if (uc $_ eq 'RUNMODE'){
			$_ = 'Runmode';
			next;
		}
		if (uc $_ eq 'STARTRUNMODE'){
			$_ = 'StartRunmode';
			next;
		}
	}
	return $pkg->SUPER::MODIFY_CODE_ATTRIBUTES($ref, @attr);
}

1;
WITH_AH
	warn "failed to load Attribute::Handlers version of CAP:AutoRunmode $@" if $@;
}



unless ($has_ah){
	eval <<'WITHOUT_AH' or die $@;
sub MODIFY_CODE_ATTRIBUTES{
	my ($pkg, $ref, @attr) = @_;
	
	my @unknown;
	foreach (@attr){
		my $u = uc $_;
		$CGI::Application::Plugin::AutoRunmode::RUNMODES{"$ref"} = 1, next
			if $u eq 'RUNMODE';
		if ($u eq 'STARTRUNMODE'){
			install_start_mode($pkg, $ref);
			next;
		}
		push @unknown, $_;
	}
	return @unknown;
}
1;
WITHOUT_AH
}



our @ISA = qw(Exporter);

# always export the attribute handlers
sub import{ 
		__PACKAGE__->export_to_level(1, @_, 'MODIFY_CODE_ATTRIBUTES'); 
		
		 # if CGI::App > 4 install the hook
		 # (unless cgiapp_prerun requested)
		 if ( @_ < 2 and $CGI::Application::VERSION >= 4 ){
		 		my $caller = scalar(caller);
		 		if (UNIVERSAL::isa($caller, 'CGI::Application')){
                	$caller->add_callback('prerun', \&cgiapp_prerun);
                }
		 }
};

our @EXPORT_OK = qw[
		cgiapp_prerun
		MODIFY_CODE_ATTRIBUTES
	];



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
	return unless defined $rm;
	
	unless (exists $rmodes{$rm}){
		# security check: disallow non-word characters 
		unless ($rm =~ /\W/){
		
			# check :Runmodes
			$self->run_modes( $rm => $rm), return
				if is_attribute_auto_runmode($self, $rm);
		
			# check delegate
			my $sub = is_delegate_auto_runmode($self, $rm);
			$self->run_modes( $rm => $sub) if $sub;
			
		}
	}
}


sub install_start_mode{
	my ($pkg, $ref) = @_;
	
	no strict 'refs';
	die "StartRunmode for package $pkg is already installed\n"
		if defined *{"${pkg}::start_mode"};
	
	my $memory;
	
	#if (ref $ref eq 'GLOB') {
	#	$memory = *{$ref}{NAME};
	#	$ref = *{$ref}{CODE};
	#}
	
	$RUNMODES{"$ref"} = 1;
	
	*{"${pkg}::start_mode"} = sub{
				 return if @_ > 1;
				 return $memory if $memory;
				 return $memory = _find_name_of_startmode_in_pkg($ref, $pkg);
			};
	
	
}





# code for this inspired by Devel::Symdump
sub _find_name_of_startmode_in_pkg{
	my ($ref, $pkg) = @_;
	no strict 'refs';
	#return *{$ref}{NAME} if ref $ref eq 'GLOB';
	while (my ($key,$val) = each(%{*{"$pkg\::"}})) {
			local(*ENTRY) = $val;
			if (defined $val && defined *ENTRY{CODE}) {
				next unless *ENTRY{CODE} eq $ref;
				# rewind "each"
				my $a = scalar keys %{*{"$pkg\::"}};
				return $key;
			}
		}

	die "failed to find name for StartRunmode code ref $ref in package $pkg\n";
}

sub is_attribute_auto_runmode{
	my($app, $rm) = @_;
	my $sub = $app->can($rm);
	return unless $sub;
	return $sub if $RUNMODES{"$sub"};
	# also check the GLOB
	#if ($has_ah){
	#	no strict 'refs';
	#	my $pkg = ref $app;
	#	warn "${pkg}::${rm}";
	#	use Data::Dumper;
	#	warn Dumper \%RUNMODES;
	#	return $sub if $RUNMODES{*{"${pkg}::${rm}"}};
	#}
	return undef;
}

sub is_delegate_auto_runmode{
	my($app, $rm) = @_;
	my $delegate = $app->param('::Plugin::AutoRunmode::delegate');
	return unless $delegate;
	return if exists $__illegal_names{$rm};
	
	my $sub = $delegate->can($rm);
	return unless $sub;
	
	# construct a closure, as we need a second
	# parameter (the delegate)
	my $closure = sub { $sub->($_[0], $delegate); };
	
	return $closure;	
}

sub is_auto_runmode{
	return is_attribute_auto_runmode(@_) || is_delegate_auto_runmode(@_);
}



1;
__END__

=head1 NAME

CGI::Application::Plugin::AutoRunmode - CGI::App plugin to automatically register runmodes

=head1 SYNOPSIS

Using subroutine attributes:

	package MyApp;
	use base 'CGI::Application';
	use CGI::Application::Plugin::AutoRunmode;
	
	sub my_run_mode : StartRunmode {
		# do something here
	}
	
	sub another_run_mode : Runmode {
		# do something else
	}
	
	# you now have two run modes
	# "my_run_mode" and "another_run_mode"
	# "my_run_mode" is the start (default) run mode


Declare that every method in a (delegate) class is a run mode. 

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
the method that implement a run mode, you do
not have to explicitly register it with CGI::App anymore.

There are two approaches: 

=over 4

=item Declare run modes with subroutine attributes. 

You can flag methods in
your CGI::App subclass with the attribute "Runmode" or "StartRunmode" (these
attributes are case-insensitive)

=item Declare that every method in a class is a run mode.

You can assign a
delegate object, all whose methods will become runmodes 

You can also mix both approaches.

Delegate runmodes receive two parameters: The first one is the CGI::App
instance, followed by the delegate instance or class name. This can be useful
if you have delegate objects that contain state.

=back

It both cases, the resulting runmodes will have the same
name as the subroutine that implements them. They are activated
by a cgiapp_prerun hook provided by this plugin (if 
you are using CGI::Application older than version 4, hooks
are not available, and you can import a cgiapp_prerun method
instead).


=head2 EXPORT

This module needs to export some symbols to do 
its job.

First of all, there are the handlers for the Runmode 
attribute.

In addition to that, the cgiapp_prerun hook is installed
in your application class.
This is not done as an export per se, but the hook installation 
is still
done in the import subroutine. Sound confusing, is confusing,
but you do not really need to know what is going on exactly,
just keep in mind that in order to let things go on, you
have to "use" the module with the default exports:

	use CGI::Application::Plugin::AutoRunmode;

and not

	use CGI::Application::Plugin::AutoRunmode ();
		# this will disable the Runmode attributes
		# DO NOT DO THIS
		

You can also explicitly import the cgiapp_prerun method.
This will disable the installation of the hook.
Basically, you only want to do this if you are using
CGI::Application prior to version 4, where hooks are
not supported.

	use CGI::Application::Plugin::AutoRunmode 
		qw [ cgiapp_prerun];
		# do this if you use CGI::Application version 3.x




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


=head2 Does it still work if I change the run mode in cgiapp_prerun ?


If you have a cgiapp_prerun method and change the run mode
there, the installed hook will not be able to catch it
(because of the ordering of hooks).

So, if you do that, you have to explicitly make this call
before returning from cgiapp_prerun:
	
   CGI::Application::Plugin::AutoRunmode::cgiapp_prerun($self);

Again, this is only necessary if you change the run mode
(to one that needs the auto-detection feature).

Also, this kind of code can be used with CGI::App 3.x
if you have a cgiapp_prerun.

=head2 StartRunmode

The attribute StartRunmode designates that subroutine to 
be the start (default) run mode. If you use this feature,
the "traditional" way of setting the start run mode (calling
C<< $self->start_mode('name') >>) is disabled and can no longer
be used in this application (including subclasses and instance
scripts).

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


=head2 Effect on the run_modes map

This module only inserts the current run mode into the
run_mode map (unless it is already in there). It does not
place any other :Runmodes there. As a result of this 
behaviour, users of AutoRunmode will most likely find the
run mode map almost completely empty. This can lead to
strange results if you expect a more complete list of possible run modes
there. At this time, there is no workaround for this.
Feel free to complain to the author if you have a requirement here.

It is possible, however, to query the AutoRunmode plugin if
an AutoRunmode exists for a given name.

  my $check = CGI::Application::Plugin::AutoRunmode::is_auto_runmode($self, $name)

This function returns a code ref if such an AutoRunmode exists. 

=head1 SEE ALSO

=over

=item *

L<CGI::Application::Plugin::AutoRunmode::FileDelegate>

=item *

L<CGI::Application>

=item *

The CGI::App wiki at 
L<http://www.cgi-app.org/>.

=back

=head1 AUTHOR

Thilo Planz, E<lt>thilo@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2004/05 by Thilo Planz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
