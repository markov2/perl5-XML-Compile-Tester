
use warnings;
use strict;

package XML::Compile::Tester;
use base 'Exporter';

our @EXPORT = qw/
 set_compile_defaults
 set_default_namespace
 create_reader
 create_writer
 writer_test
 reader_error
 writer_error
 templ_xml
 templ_perl
 compare_xml
 /;

use Test::More;
use Log::Report qw/try/;

=chapter NAME

XML::Compile::Tester - support XML::Compile related regression testing

=chapter SYNOPSIS
 use XML::Compile::Tester;
 set_compile_defaults validation => 0;
 my $reader = create_reader $schema, "my reader", $type;
 my $writer = create_writer $schema, "my writer", $type;
 my $error  = reader_error  $schema, $type, $xml;
 my $output = $templ_xml    $schema, $type, @options;
 my $output = $templ_perl   $schema, $type, @options;

=chapter DESCRIPTION

The M<XML::Compile> module suite has extensive regression testing.  Probably,
you want to do regression testing as well.  This module provide functions
which simplify writing tests for XML::Compile related distributions.

=chapter FUNCTIONS

=function set_compile_defaults OPTIONS
Each call to create a reader or writer (also indirectly) with
M<XML::Compile::Schema::compile()> will get these OPTIONS passed, on top
(and overruling) the usual settings.

=example
 set_compile_defaults include_namespaces => 1, validate => 0;
=cut

my @compile_defaults;
sub set_compile_defaults(@) { @compile_defaults = @_ }

=function set_default_namespace TESTNS
Defined which namespace to use when a relative (only localName) type
is provided.  By default, this is C<undef> (an error when used)
=cut

my $default_namespace;
sub set_default_namespace($) { $default_namespace = shift }

=function create_reader SCHEMA, COMMENT, TYPE, OPTIONS
Create a reader for TYPE.  One test is created, reporting
success or failure of the creation.

Of course, M<XML::Compile::Schema::compile()> is being called, with some
options.  By default, C<check_values> is true, and C<include_namespaces>
is false.  These values can be overruled using M<set_compile_defaults()>,
and with the OPTIONS parameter list.

=example
 my $type   = pack_type 'type-namespace', 'type-localname';
 my $reader = create_reader $schema, 'my test', $type, check_occurs => 0;

=cut

sub _reltype_to_abs($) { $_[0] =~ m/\{/ ? $_[0] : "{$default_namespace}$_[0]" }

sub create_reader($$$@)
{   my ($schema, $test, $reltype) = splice @_, 0, 3;

    my $type   = _reltype_to_abs $reltype;
    my $read_t = $schema->compile
     ( READER             => $type
     , check_values       => 1
     , include_namespaces => 0
     , @compile_defaults
     , @_
     );

    isa_ok($read_t, 'CODE', "reader element $test");
    $read_t;
}

=function create_writer SCHEMA, COMMENT, TYPE, OPTIONS
Create a writer for TYPE.  One test (in the Test::More sense) is created,
reporting success or failure of the creation.

Of course, M<XML::Compile::Schema::compile()> is being called, with some
options.  By default, C<check_values> and C<use_default_prefix> are true,
and C<include_namespaces> is false.  These values can be overruled using
M<set_compile_defaults()>, and with the OPTIONS parameter list.

=example
 my $type   = pack_type 'type-namespace', 'type-localname';
 my $writer = create_writer $schema, 'my test', $type;
=cut

sub create_writer($$$@)
{   my ($schema, $test, $reltype) = splice @_, 0, 3;
    my $type   = _reltype_to_abs $reltype;

    my $write_t = $schema->compile
     ( WRITER             => $type
     , check_values       => 1
     , include_namespaces => 0
     , use_default_prefix => 1
     , @compile_defaults
     , @_
     );

    isa_ok($write_t, 'CODE', "writer element $test");
    $write_t;
}

=function writer_test WRITER, DATA, [DOC]
Run the test with a compiled WRITER, which was created with M<create_writer()>.
When no DOC (M<XML::LibXML::Document> object) was specified, then one will
be created for you.
=cut

sub writer_test($$;$)
{   my ($writer, $data, $doc) = @_;

    $doc ||= XML::LibXML->createDocument('1.0', 'utf-8');
    isa_ok($doc, 'XML::LibXML::Document');

    my $tree = $writer->($doc, $data);
    ok(defined $tree);
    defined $tree or return;

    isa_ok($tree, 'XML::LibXML::Node');
    $tree;
}

=function reader_error SCHEMA, TYPE, XML
Parsing the XML to interpret the TYPE should return an error.  The
error text is returned.
=cut

sub reader_error($$$)
{   my ($schema, $reltype, $xml) = @_;
    my $r = create_reader $schema, "check read error $reltype", $reltype;
    defined $r or return;

    my $tree  = try { $r->($xml) };
    my $error = ref $@ && $@->exceptions
              ? join("\n", map {$_->message} $@->exceptions)
              : '';
    undef $tree
        if $error;   # there is output if only warnings are produced

    ok(!defined $tree, "no return for $reltype");
    warn "RETURNED TREE=",Dumper $tree if defined $tree;

    ok(length $error, "ER=$error");
    $error;
}

=function writer_error SCHEMA, TYPE, DATA
Translating the Perl DATA into the XML type should return a validation
error, which is returned.
=cut

sub writer_error($$$)
{   my ($schema, $reltype, $data) = @_;

    my $write = create_writer $schema, "writer for $reltype", $reltype;

    my $node;
    try { my $doc = XML::LibXML->createDocument('1.0', 'utf-8');
          isa_ok($doc, 'XML::LibXML::Document');
          $node = $write->($doc, $data);
    };

    my $error
       = ref $@ && $@->exceptions
       ? join("\n", map {$_->message} $@->exceptions)
       : '';
    undef $node if $error;   # there is output if only warnings are produced

#   my $error = $@ ? $@->wasFatal->message : '';
    ok(!defined $node, "no return for $reltype expected");
    warn "RETURNED =", $node->toString if ref $node;
    ok(length $error, "EW=$error");

    $error;
}

=function templ_xml SCHEMA, TYPE, OPTIONS
Create an example template for TYPE, as XML message.
The OPTIONS are passed to M<XML::Compile::Schema::template()>.
=cut

sub templ_xml($$@)
{   my ($schema, $test, @opts) = @_;

    my $abs = _reltype_to_abs $test;

    $schema->template
     ( XML                => $abs
     , include_namespaces => 0
     , @opts
     ) . "\n";
}

=function templ_perl SCHEMA, TYPE, OPTIONS
Create an example template for TYPE, as Perl data
structure (like Data::Dumper) The OPTIONS are passed to
M<XML::Compile::Schema::template()>.
=cut

sub templ_perl($$@)
{   my ($schema, $test, @opts) = @_;

    my $abs = _reltype_to_abs $test;

    $schema->template
     ( PERL               => $abs
     , include_namespaces => 0
     , @opts
     );
}

=function compare_xml XML, EXPECTED, [COMMENT]
Compare the XML (either a string or a M<XML::LibXML::Element>) with
the EXPECTED string.  Both sources are stripped from layout before
comparing.

In a future release, this algorithm will get improved to compare
the parsed XML node trees, not the strings.
=cut

sub compare_xml($$;$)
{   my ($tree, $expect, $comment) = @_;
    my $dump = ref $tree ? $tree->toString : $tree;

    for($dump, $expect)
    {   defined $_ or next;
        s/\>\s+/>/gs;
        s/\s+\</</gs;
        s/\>\s+\</></gs;
        s/\s*\n\s*/ /gs;
        s/\s{2,}/ /gs;
        s/\s+\z//gs;
    }
    is($dump, $expect, $comment);
}

1;