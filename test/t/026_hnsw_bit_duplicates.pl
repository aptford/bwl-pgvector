use strict;
use warnings;
use PostgresNode;
use TestLib;
use Test::More;

# Initialize node
my $node = get_new_node('node');
$node->init;
$node->start;

# Create table
$node->safe_psql("postgres", "CREATE EXTENSION vector;");
$node->safe_psql("postgres", "CREATE TABLE tst (v bit(3));");

sub insert_vectors
{
	for my $i (1 .. 20)
	{
		$node->safe_psql("postgres", "INSERT INTO tst VALUES ('111');");
	}
}

sub test_duplicates
{
	my $res = $node->safe_psql("postgres", qq(
		SET enable_seqscan = off;
		SET hnsw.ef_search = 1;
		SELECT COUNT(*) FROM (SELECT * FROM tst ORDER BY v <~> '111') t;
	));
	is($res, 10);
}

# Test duplicates with build
insert_vectors();
$node->safe_psql("postgres", "CREATE INDEX idx ON tst USING hnsw (v bit_hamming_ops);");
test_duplicates();

# Reset
$node->safe_psql("postgres", "TRUNCATE tst;");

# Test duplicates with inserts
insert_vectors();
test_duplicates();

# Test fallback path for inserts
$node->pgbench(
	"--no-vacuum --client=5 --transactions=100",
	0,
	[qr{actually processed}],
	[qr{^$}],
	"concurrent INSERTs",
	{
		"026_hnsw_bit_duplicates" => "INSERT INTO tst VALUES ('111');"
	}
);

done_testing();
