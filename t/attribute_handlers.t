#
# test to check interoperability with other plugins that use
# Attribute::Handlers
#

use Test::More tests => 8;
use strict;
use warnings;
my $has_ah;
BEGIN {
	eval '
		use Attribute::Handlers;
		$has_ah = 1;
	';
}

SKIP: {

skip 'needs Attribute::Handlers', 8 unless $has_ah;

%MyPlugin::RUNMODES = ();

eval <<'PLUGIN';
{
    package MyPlugin;

	our %RUNMODES;

    use Attribute::Handlers;

    sub CGI::Application::Authen : ATTR(CODE) {
        my ( $package, $symbol, $referent, $attr, $data, $phase ) = @_;
  		no strict 'refs';
  		$RUNMODES{$referent} = 1;
  	}

}
PLUGIN

is($@, '', 'compile plugin that defines attributes');

eval <<'MYAPP';

{
    package MyApp;

    use base qw(CGI::Application);
    use CGI::Application::Plugin::AutoRunmode qw(cgiapp_prerun);

    sub test :Authen { return 'test' }
    sub test2 :Authen :Runmode { return 'test2' }
    sub test3 :Runmode { return 'test3' }
}
MYAPP

is($@, '', 'compile MyApp that uses attributes');



$ENV{CGI_APP_RETURN_ONLY} = 1;
$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING} = 'rm=test2';

use CGI;
my $q = new CGI;

{
	my $app = new MyApp(QUERY=>$q);
	my $t = $app->run;
	like ($t , qr/test2/, 'call runmode with extra attribute');
	ok($MyPlugin::RUNMODES{$app->can('test2')}, 
		'extra attribute has been installed');
	

}


{
	$q->param(rm => 'test3');	
	my $app = new MyApp(QUERY=>$q);
	my $t = $app->run;
	like ($t , qr/test3/, 'call runmode without extra attribute');
	ok ( not ($MyPlugin::RUNMODES{$app->can('test3')}), 
		'no extra attribute has been installed when not requested');

}	
	
{
	my $testname = "try to call a not-runmode";
	$q->param(rm => 'test');
	my $app = new MyApp(QUERY=>$q);
	eval{ my $t = $app->run; };
	ok ($@ =~ /test/, $testname);
	ok($MyPlugin::RUNMODES{$app->can('test')},
		'extra attribute has been installed on non-runmode');
}
	



}
