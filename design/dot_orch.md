db: data/athousand_sorted.csv
   output:
      preview:
         - basePath: scripts/output/
         - filter: fullMatch
         - take: 15
         - runOnly
      export:
         - basePath: scripts/output/
         - filter: fullMatch
         - take: 15
         - runOnly
   variation: 
     mainline: scripts/variation1.gof
         - output: .output
            - filter: fullMatch
            - take: 15
            - runOnly
     variation1: scripts/variation2.gof
         unify:
           rook: mainline.rook
           king: mainline.king
     variation2: scripts/variation3.gof
         unify:
           rook: mainline.rook
           king: mainline.king
           bishop: variation1.bishop
     variation3: scripts/variation4.gof

run: scripts/script1.gof
db: data/athousand_sorted.csv
output: scripts/output/script1.csv
   - filter: fullMatch


run: scripts/script2.gof
db: scripts/output/script1.csv
output: scripts/script2.csv
  - filter: fullMatch
  - format: csv

