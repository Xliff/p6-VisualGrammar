use Grammar::Gatherer::WrapCache;

=begin pod

=head1 NAME

Grammer::Gatherer - non-interactive data gatherer for Perl 6 grammars

=head1 SYNOPSIS

In the file that has your grammar definition, merely load the module
in the same lexical scope:

	use Grammar::Gatherer;

	grammar Some::Grammar { ... }

=head1 DESCRIPTION

L<Grammar::Gatherer> is a stripped down version of L<Grammar::Tracerr>.
It runs through the entire grammar without stopping, collecting the results.

The resulting capture can be retrieved by accessing the Grammars HOW:

  my @results = Some::Grammar.HOW.results

Please note: Using this module is B<not> thread-safe.

=head1 AUTHOR

Clifton Wood. C<< clifton.wood@gmail.com >>

Based on L<Grammar::Tracer> by Jonathan Worthington, C<< <jnthn@jnthn.net> >>

=end pod

my class GathererGrammarHOW is Metamodel::GrammarHOW does Grammar::Gatherer::WrapCache {
    has @!results;

    method find_method($obj, $name) {
        my \cached = %!cache{$name};
        return cached if cached.DEFINITE;
        my $meth := callsame;
        if $name eq 'parse' {
             self!wrap: $name, -> $c, |args {
                 @!results = ();
                 $meth($c, |args);
             }
        }
        elsif $meth.^name eq 'NQPRoutine' || $meth !~~ Any || $meth !~~ Regex {
            self!cache-unwrapped: $name, $meth;
        }
        else {
            self!cache-wrapped: $name, $meth, -> $c, |args {
                my $result;
                try {
                    #say $name;
                    $result := $meth($c, |args);
                    CATCH { }
                }

                # Dump result.
                my $match := $result.MATCH;
                @!results.push: $name => $match;
                $result
            }
        }
    }

    method results {
      my $last;
      my @returnable = gather for @!results {
        next if .value.to < 0;
        take $last if
          $last.defined                   &&
          .value.from != $last.value.from &&
          .value.to   != $last.value.to;
        if .key eq 'TOP' {
          take $_;
          last;
        }
        $last = $_;
      }
      @returnable.unshift: @returnable.pop
        if @returnable && @returnable[*-1].key eq 'TOP';
      @returnable;
    }

    method publish_method_cache($obj) {
        # Suppress this, so we always hit find_method.
    }
}

# Export this as the meta-class for the "grammar" package declarator.
my module EXPORTHOW {
    constant grammar = GathererGrammarHOW;
}
