#!perl

## Test arrays

use strict;
use warnings;
use Test::More;
use Data::Dumper;
use DBI     ':sql_types';
use DBD::Pg ':pg_types';
use lib 't','.';
require 'dbdpg_test_setup.pl';
select(($|=1,select(STDERR),$|=1)[1]);

my $dbh = connect_database();

if (defined $dbh) {
	plan tests => 220;
}
else {
	plan skip_all => 'Connection to database failed, cannot continue testing';
}

ok( defined $dbh, 'Connect to database for array testing');

my ($sth,$result);

my $pgversion = $dbh->{pg_server_version};

if ($pgversion >= 80100) {
  $dbh->do('SET escape_string_warning = false');
}

my $SQL = q{DELETE FROM dbd_pg_test WHERE pname = 'Array Testing'};
my $cleararray = $dbh->prepare($SQL);

$SQL = q{INSERT INTO dbd_pg_test(id,pname,testarray) VALUES (99,'Array Testing',?)};
my $addarray = $dbh->prepare($SQL);

$SQL = q{SELECT testarray FROM dbd_pg_test WHERE pname= 'Array Testing'};
my $getarray = $dbh->prepare($SQL);

my $array_tests =
q![]
{}
Empty array

['']
{""}
Empty array

[['']]
{{""}}
Empty array with two levels

[[['']]]
{{{""}}}
Empty array with three levels

[[''],['']]
{{""},{""}}
Two empty arrays

[[[''],[''],['']]]
{{{""},{""},{""}}}
Three empty arrays at second level

[[],[[]]]
ERROR: must be of equal size
Unbalanced empty arrays

{}
ERROR: Cannot bind a reference
Bare hashref

[{}]
ERROR: only scalars and other arrays
Hashref at top level

[1,2,{3,4},5]
ERROR: only scalars and other arrays
Hidden hashref

[[1,2],[3]]
ERROR: must be of equal size
Unbalanced array

[[1,2],[3,4,5]]
ERROR: must be of equal size
Unbalanced array

[[1,2],[]]
ERROR: must be of equal size
Unbalanced array

[[],[3]]
ERROR: must be of equal size
Unbalanced array

[123]
{123} quote: {"123"}
Simple 1-D numeric array

['abc']
{abc} quote: {"abc"}
Simple 1-D text array

[1,2]
{1,2} quote: {"1","2"}
Simple 1-D numeric array

[[1]]
{{1}} quote: {{"1"}}
Simple 2-D numeric array

[[1,2]]
{{1,2}} quote: {{"1","2"}}
Simple 2-D numeric array

[[[1]]]
{{{1}}} quote: {{{"1"}}}
Simple 3-D numeric array

[[["alpha",2],[23,"pop"]]]
{{{alpha,2},{23,pop}}} quote: {{{"alpha","2"},{"23","pop"}}}
3-D mixed array

[[[1,2,3],[4,5,"6"],["seven","8","9"]]]
{{{1,2,3},{4,5,6},{seven,8,9}}} quote: {{{"1","2","3"},{"4","5","6"},{"seven","8","9"}}}
3-D mixed array

[q{O'RLY?}]
{O'RLY?} quote: {"O'RLY?"}
Simple single quote

[q{O"RLY?}]
{"O\"RLY?"}
Simple double quote

[[q{O"RLY?}],[q|'Ya' - "really"|],[123]]
{{"O\"RLY?"},{"'Ya' - \"really\""},{123}} quote: {{"O\"RLY?"},{"'Ya' - \"really\""},{"123"}}
Many quotes

["Test\\\\nRun"]
{"Test\\\\nRun"} quote: {"Test\\\\\\nRun"}
Simple backslash

[["Test\\\\nRun","Quite \"so\""],["back\\\\\\\\slashes are a \"pa\\\\in\"",123] ]
{{"Test\\\\nRun","Quite \"so\""},{"back\\\\\\\\\\\\slashes are a \"pa\\\\in\"",123}} quote: {{"Test\\\\\\nRun","Quite \"so\""},{"back\\\\\\\\\\\\slashes are a \"pa\\\\\\in\"","123"}}
Escape party

[undef]
{NULL}
NEED 80200: Simple undef test

[[undef]]
{{NULL}}
NEED 80200: Simple undef test

[[1,2],[undef,3],["four",undef],[undef,undef]]
{{1,2},{NULL,3},{four,NULL},{NULL,NULL}} quote: {{"1","2"},{NULL,"3"},{"four",NULL},{NULL,NULL}}
NEED 80200: Multiple undef test

!;

## Note: We silently allow things like this: [[[]],[]]

$dbh->{pg_expand_array} = 0;

for my $test (split /\n\n/ => $array_tests) {
	next unless $test =~ /\w/;
	my ($input,$expected,$msg) = split /\n/ => $test;
	my $qexpected = $expected;
	if ($expected =~ s/\s*quote:\s*(.+)//) {
		$qexpected = $1;
	}

	if ($msg =~ s/NEED (\d+):\s*//) {
		my $ver = $1;
		if ($pgversion < $ver) {
		  SKIP: {
				skip 'Cannot test NULL arrays unless version 8.2 or better', 4;
			}
			next;
		}
	}

	$cleararray->execute();
	eval {
		$addarray->execute(eval $input);
	};
	if ($expected =~ /error:\s+(.+)/i) {
		like($@, qr{$1}, "Array failed : $msg : $input");
		like($@, qr{$1}, "Array failed : $msg : $input");
	}
	else {
		is($@, q{}, "Array worked : $msg : $input");
		$getarray->execute();
		$result = $getarray->fetchall_arrayref()->[0][0];
		is($result, $expected, "Correct array inserted: $msg : $input");
	}

	eval {
		$result = $dbh->quote(eval $input );
	};
	if ($qexpected =~ /error:\s+(.+)/i) {
		my $errmsg = $1;
		$errmsg =~ s/bind/quote/;
		like($@, qr{$errmsg}, "Array quote failed : $msg : $input");
		like($@, qr{$errmsg}, "Array quote failed : $msg : $input");
	}
	else {
		is($@, q{}, "Array quote worked : $msg : $input");
		is($result, $qexpected, "Correct array quote: $msg : $input");
	}

}


## Same thing, but expand the arrays
$dbh->{pg_expand_array} = 1;

for my $test (split /\n\n/ => $array_tests) {
	next unless $test =~ /\w/;
	my ($input,$expected,$msg) = split /\n/ => $test;
	my $qexpected = $expected;
	if ($expected =~ s/\s*quote:\s*(.+)//) {
		$qexpected = $1;
	}

	if ($msg =~ s/NEED (\d+):\s*//) {
		my $ver = $1;
		if ($pgversion < $ver) {
		  SKIP: {
				skip 'Cannot test NULL arrays unless version 8.2 or better', 2;
			}
			next;
		}
	}

	$cleararray->execute();
	eval {
		$addarray->execute(eval $input);
	};
	if ($expected =~ /error:\s+(.+)/i) {
		like($@, qr{$1}, "Array failed : $msg : $input");
		like($@, qr{$1}, "Array failed : $msg : $input");
	}
	else {
		is($@, q{}, "Array worked : $msg : $input");
		$getarray->execute();
		$result = $getarray->fetchall_arrayref()->[0][0];
		$qexpected =~ s/{}/{''}/;
		$qexpected =~ y/{}/[]/;
		$qexpected =~ s/NULL/undef/g;
		$qexpected =~ s/\\\\n/\\n/g;
		$qexpected =~ s/\\\\"/\\"/g;
		$qexpected =~ s/\\\\i/\\i/g;
		$expected = eval $qexpected;
		is_deeply($result, $expected, "Correct array inserted: $msg : $input");
	}

}

$cleararray->execute();

## Pure string to array conversion testing

## Use ourselves as a valid role
my $role = 'SKIP';
if ($pgversion >= 80100) {
	$SQL = 'SELECT current_role';
	$role = $dbh->selectall_arrayref($SQL)->[0][0];
}

my $array_tests_out =
q!1
[1]
Simple test of single array element

1,2
[1,2]
Simple test of multiple array elements

1,2,3
[1,2,3]
Simple test of multiple array elements

'a','b'
['a','b']
Array with text items

0.1,2.4
[0.1,2.4]
Array with numeric items

'My"lrd','b','c'
['My"lrd','b','c']
Array with escaped items

[1]
[[1]]
Multi-level integer array

[[1,2]]
[[[1,2]]]
Multi-level integer array

[[1],[2]]
[[[1],[2]]]
Multi-level integer array

[[1],[2],[3]]
[[[1],[2],[3]]]
Multi-level integer array

[[[1]],[[2]],[[3]]]
[[[[1]],[[2]],[[3]]]]
Multi-level integer array

'abc',NULL
['abc',undef]
NEED 80200: Array with a null

['abc','NULL',NULL,NULL,123::text]
[['abc','NULL',undef,undef,'123']]
NEED 80200: Array with many nulls and a quoted int

['abc','']
[['abc','']]
Final item is empty

1,NULL
[1,undef]
NEED 80200: Last item is NULL

NULL
[undef]
NEED 80200: Only item is NULL

NULL,NULL
[undef,undef]
NEED 80200: Two NULL items only

NULL,NULL,NULL
[undef,undef,undef]
NEED 80200: Three NULL items only

[123,NULL,456]
[[123,undef,456]]
NEED 80200: Middle item is NULL

NULL,'abc'
[undef,'abc']
NEED 80200: First item is NULL

'a','NULL'
['a',"NULL"]
Fake NULL is text

[[[[[1,2,3]]]]]
[[[[[[1,2,3]]]]]]
Deep nesting

[[[[[1],[2],[3]]]]]
[[[[[[1],[2],[3]]]]]]
Deep nesting

[[[[[1]]],[[[2]]],[[[3]]]]]
[[[[[[1]]],[[[2]]],[[[3]]]]]]
Deep nesting

[[[[[1]],[[2]],[[3]]]]]
[[[[[[1]],[[2]],[[3]]]]]]
Deep nesting

1::bool
['t']
Test of boolean type

1::bool,0::bool,'true'::boolean
['t','f','t']
Test of boolean types

1::oid
[1]
Test of oid type - should not quote

1::text
['1']
Text number should quote

1,2,3
[1,2,3]
Unspecified int should not quote

1::int
[1]
Integer number should quote

'(1,2),(4,5)'::box,'(5,3),(4,5)'
['(4,5),(1,2)','(5,5),(4,3)']
Type 'box' works

!;

$Data::Dumper::Indent = 0;

for my $test (split /\n\n/ => $array_tests_out) {
	next unless $test =~ /\w/;
	my ($input,$expected,$msg) = split /\n/ => $test;
	my $qexpected = $expected;
	if ($expected =~ s/\s*quote:\s*(.+)//) {
		$qexpected = $1;
	}
	if ($msg =~ s/NEED (\d+):\s*//) {
		my $ver = $1;
		if ($pgversion < $ver) {
		  SKIP: {
				skip 'Cannot test NULL arrays unless version 8.2 or better', 1;
			}
			next;
		}
	}
	if ($pgversion < 80200) {
		if ($input =~ /SKIP/ or $test =~ /Fake NULL|boolean/) {
		  SKIP: {
				skip 'Cannot test some array items on pre-8.2 servers', 1;
			}
			next;
		}
	}

	$SQL = qq{SELECT ARRAY[$input]};
	my $result = '';
	eval {
		$result = $dbh->selectall_arrayref($SQL)->[0][0];
	};
	if ($result =~ /error:\s+(.+)/i) {
		like($@, qr{$1}, "Array failed : $msg : $input");
	}
	else {
		$expected = eval $expected;
		## is_deeply does not handle type differences
		is((Dumper $result), (Dumper $expected), "Array test $msg : $input");
	}

}

## Check utf-8 in and out of the database

SKIP: {
	eval { require Encode; };
	skip 'Encode module is needed for unicode tests', 5 if $@;

	local $dbh->{pg_enable_utf8} = 1;
	my $utf8_str = chr(0x100).'dam'; # LATIN CAPITAL LETTER A WITH MACRON

	my $quoted = $dbh->quote($utf8_str);
	is( $quoted, qq{'$utf8_str'}, 'quote() handles utf8' );
	$quoted = $dbh->quote([$utf8_str, $utf8_str]);
	is( $quoted, qq!{"$utf8_str","$utf8_str"}!, 'quote() handles utf8 inside array' );

	$dbh->do("DELETE FROM dbd_pg_test");
	$SQL = "INSERT INTO dbd_pg_test (id, testarray, val) VALUES (1, '$quoted', 'one')";
	eval {
		$dbh->do($SQL);
	};
	is($@, q{}, 'Inserting utf-8 into an array via quoted do() works');

	$SQL = "SELECT id, testarray, val FROM dbd_pg_test WHERE id = 1";
	$sth = $dbh->prepare($SQL);
	$sth->execute();
	$result = $sth->fetchall_arrayref()->[0];
	my $t = q{Retreiving an array containing utf-8 works};
	my $expected = [1,[$utf8_str,$utf8_str],'one'];
	is_deeply($result, $expected, $t);

	$dbh->do("DELETE FROM dbd_pg_test");
	$SQL = "INSERT INTO dbd_pg_test (id, testarray, val) VALUES (?, ?, 'one')";
	$sth = $dbh->prepare($SQL);
	eval {
		$sth->execute(1,['Bob',$utf8_str]);
	};
	is($@, q{}, 'Inserting utf-8 into an array via prepare and arrayref works');

	$SQL = "SELECT id, testarray, val FROM dbd_pg_test WHERE id = 1";
	$sth = $dbh->prepare($SQL);
	$sth->execute();
	$result = $sth->fetchall_arrayref()->[0];
	$t = q{Retreiving an array containing utf-8 works};
	$expected = [1,['Bob',$utf8_str],'one'];
	is_deeply($result, $expected, $t);

	$dbh->do("DELETE FROM dbd_pg_test");
	$SQL = qq{INSERT INTO dbd_pg_test (id, testarray, val) VALUES (1, '{"noutfhere"}', 'one')};
	$dbh->do($SQL);
	$SQL = "SELECT testarray FROM dbd_pg_test WHERE id = 1";
	$sth = $dbh->prepare($SQL);
	$sth->execute();
	$result = $sth->fetchall_arrayref()->[0][0];
	ok( !Encode::is_utf8($result), 'Non utf-8 inside an array is not return as utf-8');
	$sth->finish();
}

cleanup_database($dbh,'test');
$dbh->disconnect;
