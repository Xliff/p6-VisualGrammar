grammar T {
  regex TOP { ^ <ab>+  $ }
  regex ab  { <a> \v* }
  token a   { 'a'+<b>* }
  token b   { 'b'+ }
}
