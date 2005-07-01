# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;

BEGIN { plan tests => 14 };

use Text::Templet;

ok(1);

use vars qw( $tv $c );

$tv = "Test Variable";

sub sub1() {return 'Sub 1 Returns';}
sub switch1() {return 'C2';}

## send script output to STDERR to keep it out of STDOUT
## which is used by diagnostics printed from ok()
## Test::Harness bombs out if they are mixed together
select(STDERR);

ok(Templet('Hello, World!\t'),'');
ok(Templet('$tv\t'),'');
ok(Templet('Begin $tv End\t'),'');
ok(Templet('<% print $tv; "" %>\t'),'');
ok(Templet('Begin <% print $tv; "" %> End\t'),'');
ok(Templet('<% "SKIP" %>This test has failed<%SKIP%>\t'),'');
ok(Templet('Begin <% "SKIP" %>This test has failed<%SKIP%> End\t'),'');
ok(Templet('<% $c = 0; %><%I1%>$c <% "I1" if ++$c < 10 %>\t'),'');
ok(Templet('Begin <% $c = 0; %><%I1%>$c <% "I1" if ++$c < 10 %> End\t'),'');
ok(Templet('<% print &sub1(); "" %>\t'),'');
ok(Templet('Begin <% print &sub1(); "" %> End\t'),'');
ok(Templet('<% &switch1() %><%C1%>Choice 1<%"END_SWITCH1"%><%C2%>Choice2<%END_SWITCH1%>\t'),'');
ok(Templet('Begin <% &switch1() %><%C1%>Choice 1<%"END_SWITCH1"%><%C2%>Choice2<%END_SWITCH1%> End\t'),'');
