#!/usr/bin/env perl

use strict;
use warnings;

my $min_line = $ARGV[0];
shift @ARGV;
my $max_line = $ARGV[0];
shift @ARGV;

my $patch_cmd;
if (defined $ARGV[0] and $ARGV[0] =~ m{^[^-]}) {
    $patch_cmd = "@ARGV";
} else {
    $patch_cmd = "patch @ARGV";
}
my $reverse = grep /^(--reverse|-R)$/, @ARGV;

my $lineno = 0;
my $original = "";
my $wheat = "";
my $chaff = "";
my $state = undef;
my $hunk_wheat = undef;
my $hunk_chaff = undef;
my $hunk_header = undef;

sub compute_hunk_header {
    my $original_header = shift;
    my $hunk = shift;
    my $old_lines = 0;
    my $new_lines = 0;
    for (split /\n/, $hunk) {
        $old_lines++ if m{^[ -]};
        $new_lines++ if m{^[ +]};
    }
    my $updated_header = $original_header =~ s/^@@ -(\d+),\d+\s+\+(\d+),\d+ @@(.*)/@@ -$1,$old_lines +$2,$new_lines @\@$3/mr;
    return $updated_header;
}

sub finish_hunk {
    return unless defined $hunk_header;
    if ($hunk_wheat =~ m{^[-+]}m) {
        $wheat .= (compute_hunk_header $hunk_header, $hunk_wheat). $hunk_wheat;
    }
    $chaff .= (compute_hunk_header $hunk_header, $hunk_chaff) . $hunk_chaff;
    $hunk_header = undef;
}

while (<STDIN>) {
    ++$lineno;
    $original .= $_;
    if (m{^diff}) {
        finish_hunk();
        $state = "diff header";
    }
    if (m{^@@}) {
        finish_hunk();
        $state = "diff hunk";
        $hunk_header = $_;
        $hunk_wheat = "";
        $hunk_chaff = "";
        next;
    }
    if ($state eq "diff header") {
        $wheat .= $_;
        $chaff .= $_;
        next;
    }
    my $include = m{^ } || ($lineno >= $min_line && $lineno <= $max_line);
    if ($include) {
        $hunk_wheat .= $_;
        $hunk_chaff .= $_ if m{^ };
        if ($reverse ? m{^[-]} : m{^\+}) {
            $hunk_chaff .= " " . substr $_, 1;
        }
    } else {
        if ($reverse ? m{^\+} : m{^-}) {
            $hunk_wheat .= " " . substr $_, 1;
        }
        $hunk_chaff .= $_;
    }
}
finish_hunk();

open PATCH_COMMAND, "|-", "$patch_cmd 1>&2" or die "patch-range.pl: error running '$patch_cmd': $!";
print PATCH_COMMAND $wheat;
if (not close PATCH_COMMAND) {
    print $original;
    print STDERR "patch-range.pl: error running:\n" . "\$ $patch_cmd << EOF\n$wheat" . "EOF\n";
    exit 1;
}
print $chaff;
