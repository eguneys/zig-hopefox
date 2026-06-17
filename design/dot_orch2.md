src: database.db
script.gof:
  filterA: @preview
    script2.gof:
      filterA
      filterB: @preview(visualTake=10)
        script3.gof:
          filterA
          filterB
  filterB
  filterC: @preview