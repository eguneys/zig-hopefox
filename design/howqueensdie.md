## How Queens Die? Analysing 4.6 million puzzle database

How many ways can you lose your queen on a chess game? There are different levels of complexity where the loss of a queen becomes unavoidable due to a blunder, and presents itself as a chess puzzle in the Lichess puzzle database. In this blog post we will try to answer this question. From obvious hanging of a queen, to knight forks or bishop discoveries, to queen traps or desperade queen sacrifices. We will count them all and present statistical data extracted from 4.6 million Lichess puzzles along with all the examples taken from actual games played on Lichess.

On the next phase, we will delve deeper into side examples, exceptions, counter attacks, that break the pattern of those simple obvious tactics we presented in the first phase. Along with real examples, that will make much more interesting content, attracting more advanced players.

Finally, we will give a sneak peek to the method we use on the research of this content, namely GofChess Language 2.0, a much more modern and improved successor of the earlier version, which [we also introduced this year in May](https://lichess.org/@/heroku/blog/gofchess-a-technical-dive-into-formalization-of-chess-tactics/KULHdYDn).

## Bishop Checks King with a Discovered attack on Hanging Queen


