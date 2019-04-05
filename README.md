# Visual Grammar for Perl6

![Screenshot](/grabs/VisualGrammar-interface.png?raw=true "VisualGrammar Interface")

This is an extremely experimental project, and getting it to work requires checking out several git repositories.

Here are the installation instructions for those of you wanting to experiment:

- First, check out my forthcoming Pango module:

```
$ git clone https://github.com/Xliff/p6-Pango.git
```

- Then checkout p6-GtkPlus

```
$ git clone https://github.com/Xliff/p6-GtkPlus.git
```

- And finally, checkout Visual Grammar

```
$ git clone https://github.com/Xliff/p6-VisualGrammar.git
```

- Now finally run the project. Be prepared to wait a LONG time the first time you do this (Sorry!).  Be sure to adjust the -I directives for your environment.

```
$ cd p6-VisualGrammar
$ perl6 --stagestats -I../p6-Pango/lib -I../p6-GtkPlus/lib -Ilib visual-grammar.pl6
```

Please share compile times and your environment from the last command, [here](/../../issues/1).

I will work on making this all less complex, in time. Thanks for your interest!

