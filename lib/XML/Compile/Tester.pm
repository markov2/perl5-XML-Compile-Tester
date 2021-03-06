# This code is part of distribution XML-Compile-Tester.  Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::Tester;
use base 'Exporter';

use warnings;
use strict;

our @EXPORT = qw/
 set_compile_defaults
 set_default_namespace
 reader_create create_reader
 writer_create create_writer
 writer_test
 reader_error
 writer_error
 templ_xml
 templ_perl
 templ_tree
 compare_xml
 /;

use Test::More;
use Data::Dumper;
use Log::Report        qw/try/;

my $default_namespace;
my @compile_defaults;

=chapter NAME

XML::Compile::Tester - support XML::Compile related regression testing

=chapter SYNOPSIS
 use XML::Compile::Tester;

 # default additional compile flags, avoids repetition
 set_compile_defaults(validation => 0, @other_opts);
 set_compile_defaults();  # reset

 # set default namespace, such that $type only needs to use local
 my $ns     = 'some-schemas-targetNamespace';
 my $type   = pack_type($ns, 'localName'); # X::C::Util
 set_default_namespace($ns);
 my $type   = 'localName'; # now implicit in $ns

 my $reader = reader_create($schema, "my reader", $type, @opts);
 my $data   = $reader->($xml);  # $xml is string, filename, node

 my $writer = writer_create($schema, "my writer", $type, @opts);
 my $xml    = $writer->($doc, $data);
 my $xml    = writer_test($writer, $data);

 my $rerror = reader_error($schema, $type, $xml);
 my $werror = writer_error($schema, $type, $data);

 my $output = templ_xml($schema, $type, @options);
 my $output = templ_perl($schema, $type, @options);

=chapter DESCRIPTION

The M<XML::Compile> module suite has extensive regression testing.  Probably,
you want to do regression testing as well.  This module provide functions
which simplify writing tests for XML::Compile related distributions.

=chapter FUNCTIONS

=section Reader checks

=function reader_create $schema, $comment, $type, %options
Create a reader for $type.  One test is created, reporting
success or failure of the creation.

Of course, M<XML::Compile::Schema::compile()> is being called, with some
options.  By default, C<check_values> is true, and C<include_namespaces>
is false.  These values can be overruled using M<set_compile_defaults()>,
and with the %options parameter list.

=example reader_create
 my $type   = pack_type('namespace', 'localName');
 my $reader = reader_create($schema, 'my test', $type
   , check_occurs => 0, @other_options);

 my $data   = $reader->($xml);
 is_deeply($data, $expected, 'my test');  # Test::More
 cmp_deeply($data, $expected, 'my test'); # Test::Deep

 # alternative for $type:
 set_default_namespace('namespace');
 my $reader = reader_create($schema, 'my test', 'localName'
   , check_occurs => 0, @other_options);

=cut

# not using pack_type, which avoids a recursive dependency to XML::Compile
sub _reltype_to_abs($)
{   defined $default_namespace && substr($_[0], 0,1) eq '{'
      ? "{$default_namespace}$_[0]" : $_[0] }

sub reader_create($$$@)
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
*create_reader = \&reader_create;  # name change in 0.03

=function reader_error $schema, $type, $xml
Parsing the $xml to interpret the $type should return an error.  The
error text is returned.

=example reader_error
 my $error = reader_error($schema, $type, <<_XML);
 <test1>...</test1>
 _XML

 is($error, 'error text', 'my test');
 like($error, qr/error pattern/, 'my test');
=cut

sub reader_error($$$)
{   my ($schema, $reltype, $xml) = @_;
    my $r = reader_create $schema, "check read error $reltype", $reltype;
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

=section Writer checks

=function writer_create $schema, $comment, $type, %options
Create a writer for $type.  One test (in the Test::More sense) is created,
reporting success or failure of the creation.

Of course, M<XML::Compile::Schema::compile()> is being called, with some
options.  By default, C<check_values> and C<use_default_namespace> are true,
and C<include_namespaces> is false.  These values can be overruled using
M<set_compile_defaults()>, and with the %options parameter list.

=example writer_create
 set_default_namespace('namespace');
 my $writer = writer_create($schema, 'my test', 'test1');

 my $doc    = XML::LibXML::Document->new('1.0', 'UTF-8');
 my $xml    = $writer->($doc, $data);
 compare_xml($xml, <<_EXPECTED, 'my test');
   <test1>...</test1>
 _EXPECTED

 # implicit creation of $doc
 my $xml    = writer_test($writer, $data);
=cut

sub writer_create($$$@)
{   my ($schema, $test, $reltype) = splice @_, 0, 3;
    my $type   = _reltype_to_abs $reltype;

    my $write_t = $schema->compile
     ( WRITER                => $type
     , check_values          => 1
     , include_namespaces    => 0
     , use_default_namespace => 1
     , @compile_defaults
     , @_
     );

    isa_ok($write_t, 'CODE', "writer element $test");
    $write_t;
}
*create_writer = \&writer_create;  # name change in 0.03

=function writer_test $writer, $data, [$doc]
Run the test with a compiled $writer, which was created with M<writer_create()>.
When no $doc (M<XML::LibXML::Document> object) was specified, then one will
be created for you.

=cut

sub writer_test($$;$)
{   my ($writer, $data, $doc) = @_;

    $doc ||= XML::LibXML->createDocument('1.0', 'UTF-8');
    isa_ok($doc, 'XML::LibXML::Document');

    my $tree = $writer->($doc, $data);
    ok(defined $tree);
    defined $tree or return;

    isa_ok($tree, 'XML::LibXML::Node');
    $tree;
}

=function writer_error $schema, $type, $data
Translating the Perl $data into the XML type should return a validation
error, which is returned.

=example writer_error
 my $error = writer_error($schema, $type, $data);

 is($error, 'error text', 'my test');
 like($error, qr/error pattern/, 'my test');
=cut

sub writer_error($$$)
{   my ($schema, $reltype, $data) = @_;

    my $write = writer_create $schema, "writer for $reltype", $reltype;

    my $node;
    try { my $doc = XML::LibXML->createDocument('1.0', 'UTF-8');
          isa_ok($doc, 'XML::LibXML::Document');
          $node = $write->($doc, $data);
    };

    my $error
       = ref $@ && $@->exceptions
       ? join("\n", map $_->message, $@->exceptions)
       : '';
    undef $node if $error;   # there is output if only warnings are produced

#   my $error = $@ ? $@->wasFatal->message : '';
    ok(!defined $node, "no return for $reltype expected");
    warn "RETURNED =", $node->toString if ref $node;
    ok(length $error, "EW=$error");

    $error;
}

#--------------
=section Check templates

=function templ_xml $schema, $type, %options
Create an example template for $type, as XML message.
The %options are passed to M<XML::Compile::Schema::template()>.

=example templ_xml
 my $out = templ_xml($schema, $type, show => 'ALL');
 is($out, $expected);
=cut

sub templ_xml($$@)
{   my ($schema, $test, @opts) = @_;

    my $abs = _reltype_to_abs $test;

    $schema->template
     ( XML                => $abs
     , include_namespaces => 1
     , @opts
     ) . "\n";
}

=function templ_perl $schema, $type, %options
Create an example template for $type, as Perl data
structure (like Data::Dumper) The %options are passed to
M<XML::Compile::Schema::template()>.

=example templ_perl
 my $out = templ_perl($schema, $type, show => 'ALL');
 is($out, $expected);
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

=function templ_perl $schema, $type, %options
=cut

sub templ_tree($$@)
{   my ($schema, $test, @opts) = @_;
    my $abs = _reltype_to_abs($test);

    $schema->template
     ( TREE               => $abs
     , @opts
     );
}


=section Helpers

=function set_compile_defaults %options
Each call to create a reader or writer (also indirectly) with
M<XML::Compile::Schema::compile()> will get these %options passed, on top
(and overruling) the usual settings.

=example
 # defaults for XML::Compile::Schema::compile()
 set_compile_defaults(include_namespaces => 1, validate => 0
   , sloppy_intergers => 1, sloppy_floats => 1);

 set_compile_defaults();   # reset
=cut

sub set_compile_defaults(@) { @compile_defaults = @_ }

=function set_default_namespace $testns
Defined which namespace to use when a relative (only localName) type
is provided.  By default, this is C<undef> (an error when used)
=cut

sub set_default_namespace($) { $default_namespace = shift }

=function compare_xml $created, $expected, [$comment]
Compare the $created XML (either a string or an M<XML::LibXML::Element>)
with the $expected string.  Both sources are stripped from layout before
comparing.

In a future release, this algorithm will get improved to compare
the parsed XML node trees, not the strings.

=example compare_xml
 compare_xml($xml, <<_XML, 'my test');
   <test1>...</test1>
 _XML
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
