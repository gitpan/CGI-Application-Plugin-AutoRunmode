#!perl -T

use Test::More tests => 4;
use strict;
use warnings;
BEGIN { use_ok('CGI::Application::Plugin::AutoRunmode') };

$ENV{CGI_APP_RETURN_ONLY} = 1;

{
	package MyTestApp;
	use base 'CGI::Application';
	use CGI::Application::Plugin::AutoRunmode
		qw [ cgiapp_prerun ]; # for CGI::App 3 compatibility
 	sub mode1 : StartRunmode {
	 	'called mode1';
	 }
}



{
	package MyTestSubApp;
	use base 'MyTestApp';
 	sub mode2 : StartrunMode {
	 	'called mode2';
	 }
}




	{
		my $testname = "autodetect startrunmode ";
	
		my $app = new MyTestApp();
		my $t = $app->run;
		ok ($t =~ /called mode1/, $testname);
	}
	
	{
		my $testname = "autodetect startrunmode in subclass and case-insensitive ";
	
		my $app = new MyTestSubApp();
		my $t = $app->run;
		ok ($t =~ /called mode2/, $testname);
	}
	
	{
		my $testname = "cannot install two StartRunmodes ";
		eval <<'CODE';
		package MyTestAppBroken;
		use base 'CGI::Application';
		use CGI::Application::Plugin::AutoRunmode;
 		sub mode1 : StartRunmode {
	 		'called mode1';
		 }
		sub mode2 : StartRunmode {
		 	'called mode2';
		}
CODE
		ok ($@ =~ /StartRunmode for package MyTestAppBroken is already installed/, $testname);
	}


