#!perl -T
#########################


use Test::More tests => 3;
BEGIN { use_ok('CGI::Application::Plugin::AutoRunmode::FileDelegate') };

#########################
# Test CGI::App class
{ 
	package MyTestApp;
	use base 'CGI::Application';
	use CGI::Application::Plugin::AutoRunmode 
		qw [ cgiapp_prerun];
		
	sub setup{
		my $self = shift;
		$self->param(
			'::Plugin::AutoRunmode::delegate' => 
				new CGI::Application::Plugin::AutoRunmode::FileDelegate('t/runmodes') 
		);
	}
}


$ENV{CGI_APP_RETURN_ONLY} = 1;
$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING} = 'rm=mode1&tainted=' . $ENV{PATH};

use CGI;
my $q = new CGI;
{
	my $testname = "call delegate runmode";
	
	my $app = new MyTestApp(QUERY=>$q);
	my $t = $app->run;
	ok ($t =~ /called mode1/, $testname);
}


{	
	my $testname = "security check - try to escape";
	$q->param(rm => '../runmodes/mode1');
	my $app = new MyTestApp(QUERY=>$q);
	eval{ my $t = $app->run; };
	ok ($@ =~ /^No such/, $testname);
}




