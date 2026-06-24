## How Queens Die: Analysing a 4.6 Million Puzzle Database

How many ways can you lose your queen in a chess game? There are different levels of complexity where the loss of a queen becomes unavoidable due to a blunder, and presents itself as a chess puzzle in the Lichess puzzle database. In this blog post we will try to answer this question. From obvious hanging of a queen, to knight forks or bishop discoveries, to queen traps or desperade queen sacrifices. We will count them all and present statistical data extracted from 4.6 million Lichess puzzles. We will break down the numbers and look at real examples taken from actual games.

Then, we will delve deeper into side examples, exceptions, counter attacks, that break the pattern of those simple obvious tactics we present in the first section — making content designed to appeal to more advanced players.

Finally, we will give you a sneak peek to the method behind this research, namely **GofChess Language 2.0**, the modernized and significantly improved successor of the earlier version [we introduced this past May](https://lichess.org/@/heroku/blog/gofchess-a-technical-dive-into-formalization-of-chess-tactics/KULHdYDn).

## Basic Patterns

Our overall conclusion over finding these basic patterns is, Queen can always be the first one to save when under a threat, apart from a checkmate, thus the other side of the double threat is usually to the king, where as the queen is lost, as the king escapes. Let's get started.

### Bishop Checks King with a Discovered attack on Hanging Queen

### Bishop Skewers King and Queen

### Knight Forks King and Queen

### Pawn Forks King and Queen

### Pawn Checks King with a Discovered attack on Hanging Queen

### Immediately Hanging the Queen

### Queen Traps

## Advanced Exceptions to Basic Patterns

## Methodology of GofChess Language v2.0

## Conclusion

To conclude this chapter, I would like to thank the Lichess Team, for presenting this amazing ecosystem, outreach to the community and tools that guided me with this entire research.

We are happy to hear your best wishes to continue this amazing journey, and share our experiences with all of you.

May the Queens of the game of chess bring us all the good luck in the universe that will never die.

PS: I feel like I am having a déjà vu.