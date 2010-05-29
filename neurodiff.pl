#!/usr/bin/perl

# NEUROdiff:
#
# NEURO : un-jumble of RENUO, which stands for Regular Expression aNd UnOrdered.
#
# Original author: Gurjeet Singh ( singh.gurjeet@gmail.com )
#
# 06 Aug 2008 : First implementation
# 07 Aug 2008 : Added more comments and extra output for the case when one file
#                 ends but the other one doesn't.
# 20 Jun 2009 : Improve perfomance boost by sorting the unordered group before
#                 comparing them. Do this only if the UO group does not contain
#                 any line containing RE.

use strict;
use warnings;

sub usage
{
	print "Usage: neurodiff.pl <expected-filename> <result-filename>\n";
	return;
}

# file handles for expected and results files
my $EXPECTED;
my $RESULT;

my $expected; # line iterator for EXPECTED file
my $result;   # line iterator for RESULT file

my $re;       # the Regular Expression part of a line which starts with ?

my $insideuo; # boolean, representing if we are INSIDE an UnOrdered set of lines

my $skipresultline;  # Skip reading the RESULT file's line for one iteration 

my $iuo;             # counter I for counting lines within an UnOrdered set
my $seenspecialinuo; # Seen special marker inside unordered group

my $elno;            # Expected file's Line Number being processed
my $rlno;            # Result file's Line Number being processed

my $rc = 0;              # Return Code

my @earr = ( [], [] ); # 2-dimensional ARRay to keep Expected file's unmatched lines from an unordered set
my @rarr = ( [], [] ); # 2-dimensional ARRay to keep Result file's unmatched lines from unordered set

# we require exactly 2 arguments
if( @ARGV != 2 )
{
	usage();
	exit(1);
}

# initialize (almost) everything
open $EXPECTED, "<", $ARGV[0] or die $!;
open $RESULT  , "<", $ARGV[1] or die $!;

$elno = $rlno = 0;

$insideuo = 0;
$skipresultline = 0;
$iuo = 0;

# process all lines from both the files
while( 1 )
{
	undef $!;

	my $matched = 1;

	$expected = <$EXPECTED>;
	++$elno;

	undef $!;

	# do not read result file if we decided not to do so in the previous iteration
	if( !$skipresultline )
	{
		$result = <$RESULT>;
		++$rlno;
	}
	else
	{
		$skipresultline = 0;
	}

	# one file finished but not the other
	if( ( !defined( $expected ) || !defined( $result ) )
		&& ( defined( $expected ) || defined( $result ) ) )
	{
		$rc = 1;

		if( !defined( $expected ) )
		{
			print "--- left file ended before right file at $elno\n";
			print "$result\n";
		}
		else
		{
			print "--- right file ended before left file at $rlno\n";
			print "$expected\n";
		}

		last; # while( 1 )
	}

	# both files finished
	if( !defined( $expected ) && !defined( $result ) )
	{
		last; # while( 1 )
	}

	# chomp away...
	# Apart from getting rid of extra newlines in messages, this will also help
	# us be agnostic about platform specific newline sequences.
	# 
	# Correction: Apparently the above assumption is not true (found the hard
	# way :( ).
	# If the file was generated on Windows (CRLF), the Linux version of chomp
	# will trim only \n and leave \r. Had to use dos2unix on the out files to
	# make this script work.
	chomp( $expected );
	chomp( $result );

	# if the line from expected file starts with a ?, treat it specially
	if( $expected =~ /^\?.*/ )
	{
		# extract the Regular Expression
		$re = substr $expected, 1;

		# If this is the beginning of an UnOrdered set of lines
		if( $re eq 'unordered' )
		{
			if( $insideuo )
			{
				printf <STDERR>, "Nesting of 'unordered' blocks is not allowed\n";
				exit( 1 );
			}

			# reset the variables for the UO set.
			$iuo = 0;
			$insideuo = 1;
			$seenspecialinuo = 0;

			# read the next line from Expected file, but not from Result file
			$skipresultline = 1;

			next;
		}

		# end of an UnOrderd set of lines
		if( $re eq '/unordered' )
		{
			if( !$insideuo )
			{
				printf <STDERR>, "'/unordered' line found without a matching 'unordered' line\n";
				exit( 1 );
			}

			$insideuo = 0;

			# read the next line from Expected file, but not from Result file
			$skipresultline = 1;

			# If there were some lines containing RE, do comparison the hard way
			if( $seenspecialinuo )
			{
				# begin the (m*n) processing of the two arrays. These arrays
				# contain the set of unmatched lines from respective files
				# printf STDOUT "doing seenspecialinuo\n";
				foreach my $eelemref ( @earr )
				{
					my $i = 0;

					my $eelem = $eelemref->[1];

					foreach my $relemref ( @rarr )
					{
						my $relem = $relemref->[1];

						$matched = 1;

						# treat these lines the same as we threat the others;
						# that is, if an 'expected' line starts with a '?', we
						# perform Regular Expression match, else we perform
						# normal comparison.

						if( $eelem =~ /^\?.*/ )
						{
							my $tmpre = substr $eelem, 1;

							if( $relem !~ /^$tmpre$/ )
							{
								$matched = 0;
							}
							else
							{
								last;
							}
						}
						elsif( $eelem ne $relem )
						{
							$matched = 0;
						}
						else
						{
							last;
						}

						++$i;
					} # foreach @rarr

					if( !$matched )
					{
						print "--- $eelemref->[0]/0 ---\n";
						print "< $eelem\n";
					}
					else
					{
						splice @rarr, $i, 1;
					}
				} # foreach @earr

				# print out all the Result lines that couldn't be matched in an unordered set.
				foreach my $relemref ( @rarr )
				{
					print "--- 0/$relemref->[0] ---\n";
					print "> $relemref->[1]\n";
				}
			}
			else	# if there's no line containing an RE in this UO group,
					# do it efficiently
			{
				# printf STDOUT "NOT doing seenspecialinuo\n";
				# sort both arrays based on the text.
				@earr = sort { $a->[1] cmp $b->[1] } @earr;
				@rarr = sort { $a->[1] cmp $b->[1] } @rarr;

				my $min_len = (scalar(@earr) <= scalar(@rarr) ? scalar(@earr) : scalar(@rarr) );
				my $i;

				for( $i = 0; $i < $min_len; ++$i )
				{
					my $eelem = $earr[$i][1];
					my $relem = $rarr[$i][1];

					# treat these lines the same as we threat the others; that is, if an
					# 'expected' line starts with a '?', we perform Regular Expression
					# match, else we perform normal comparison.

					if( $eelem =~ /^\?.*/ )
					{
						my $tmpre = substr $eelem, 1;

						if( $relem !~ /^$tmpre$/ )
						{
							print "--- $earr[$i][0]/$rarr[$i][0] ---\n";
							print "< $eelem\n";
							print "> $relem\n";
						}
					}
					elsif( $eelem ne $relem )
					{
						print "--- $earr[$i][0]/$rarr[$i][0] ---\n";
						print "< $eelem\n";
						print "> $relem\n";
					}
				}

				for( my $j = $i; $j < scalar(@earr); ++$j )
				{
					print "--- $earr[$i][0]/0 ---\n";
					print "< $earr[$i][1]\n";
				}

				for( my $j = $i; $j < scalar(@rarr); ++$j )
				{
					print "--- 0/$earr[$i][0] ---\n";
					print "> $rarr[$i][1]\n";
				}
			} # else part of if( $seenspecialinuo )

			# reset the array variables to reclaim memory
			@earr = @rarr = ();

			next; # while( 1 )

		} # if re == '/unordered'

		# it is not an 'unordered' marker, so do regular Regular Expression match
		if( $result !~ /^$re$/ )
		{
			$matched = 0;
		}

	} # if $expected like ?.*

	# $expected doesn't begin with the special marker, so do normal comparison
	elsif( $expected ne $result )
	{
		$matched = 0;
	}

	if( !$matched )
	{
		# if the lines did not match, and if we are comparing an unordered set of lines,
		# then save the lines for processing later.
		if( $insideuo )
		{
			$earr[$iuo][0] = $elno;
			$earr[$iuo][1] = $expected;

			$rarr[$iuo][0] = $rlno;
			$rarr[$iuo][1] = $result;

			if( !$seenspecialinuo && $expected =~ /^\?.*/ )
			{
				$seenspecialinuo = 1;
			}

			++$iuo;
		}
		else # print out the difference
		{
			print "--- $elno/$rlno ---\n";
			print "< $expected\n";
			print "> $result\n";
		}
	}
}

close $EXPECTED;
close $RESULT;

exit( $rc );
