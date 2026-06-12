
```
rook_t *Checks king_o *becomes rook2
          *Blockedby rook3 *becomes rook4
                                       .attackedby bishop
                                       .defendedby queen
```

```
bishop
      .eyes pawn
                .defendedby king
king
    .home .near rook

queen
     .pins pawn2 .to king

knight
     .center
     .attackedby pawn3
                      .ffile
     .blocksescapesquaresof king

bishop
      *Sacrificeson pawn *becomes bishop2
      .checks king
             .cannotbecaptured
             .cannotbeblocked

king
    .haslegalmoveto sq
                      .corner
    .cancapture bishop
                      .hanging

king *Captures bishop2 *becomes king2

queen *Forks king2  *and                       pawn4 *becomes queen2
                  .hasonelegalmoveto king           .hanging

king2 *Movesto king *becomes king3

queen2 *captures pawn4 *becomes queen3
       .withcheck
```