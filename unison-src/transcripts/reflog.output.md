First we make two changes to the codebase, so that there's more than one line
for the `reflog` command to display:

```unison
x = 1
```

```ucm

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      x : Nat

```
```ucm
.> add

  ⍟ I've added these definitions:
  
    x : Nat

```
```unison
y = 2
```

```ucm

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      y : Nat

```
```ucm
.> add

  ⍟ I've added these definitions:
  
    y : Nat

.> view y

  y : Nat
  y = 2

```
```ucm
.> reflog

  Here is a log of the root namespace hashes, starting with the
  most recent, along with the command that got us there. Try:
  
    `fork 2 .old`             
    `fork #k4l5pp6m04 .old`   to make an old namespace
                              accessible again,
                              
    `reset-root #k4l5pp6m04`  to reset the root namespace and
                              its history to that of the
                              specified namespace.
  
       When   Root Hash     Action
  1.   now    #90f8seam5j   add
  2.   now    #k4l5pp6m04   add
  3.   now    #v4vfn849gt   builtins.merge
  4.          #sg60bvjo91   history starts here
  
  Tip: Use `diff.namespace 1 7` to compare namespaces between
       two points in history.

```
If we `reset-root` to its previous value, `y` disappears.
```ucm
.> reset-root 2

  Done.

```
```ucm
.> view y

  ⚠️
  
  The following names were not found in the codebase. Check your spelling.
    y

```
