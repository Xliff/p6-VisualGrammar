role Grammar::Gatherer::WrapCache {
    has %!cache;

    method !cache-unwrapped(Str $name, Mu \unwrapped) {
        %!cache{$name} := unwrapped;
        unwrapped
    }

    method !wrap(Str $name, \wrapped) {
        %!cache{$name} := wrapped;
        wrapped;
    }

    method !cache-wrapped(Str $name, Mu \orig, \wrapped) {
        my role Forward {
            has Mu $.NFA;
            method SET-ORIG(Mu \orig --> Nil) {
                my Mu $raw-meth = orig.^lookup('NFA');
                $!NFA := $raw-meth(orig);
            }
        }
        wrapped does Forward;
        wrapped.SET-ORIG(orig);
        %!cache{$name} := wrapped;
        wrapped
    }
}
