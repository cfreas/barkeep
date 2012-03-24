# A smart search box that helps the user find search parameters

class window.SmartSearch
  constructor: (@searchBox) ->

  # Allow for some synonym keywords
  SYNONYMS =
    author: "authors"
    branch: "branches"
    repo: "repos"


  # Parse a partial search string so we can help complete the search query for the user.
  # Returns a object with the key: set to the last key the user had typed and partialValue: to the last value
  # being typed. It is possible for both to be empty or for partialValue: to be empty.
  parsePartialQuery: (searchString) ->
    currentKey = ""
    currentValue = ""
    state = "Key" # two possible states: "Key" or "Value"

    stateMachine = (char) ->
      if (state == "Key")
        if (char == ":" and currentKey != "")
          state = "Value"
        else if (char != ' ')
          currentKey += char
        else if (char == ' ')
          currentKey = ""
      else if state ==  "Value"
        if (char == ",")
          currentValue = ""
        else if (char == " ")
          state = "Key"
          currentKey = ""
          currentValue = ""
        else
          currentValue += char

    # remove spaces around separators '':'' and '',''
    searchString = searchString.replace(/\s+:/g, ":").replace(/:\s+/g, ":").
        replace(/\s+,/g, ",").replace(/,\s+/g, ",")

    stateMachine(char) for char in searchString.split ''

    key = if SYNONYMS[currentKey]? then SYNONYMS[currentKey] else currentKey

    { key: key, partialValue: currentValue }


  parseSearch: (searchString) ->
    # This could be repo, author, etc. If it is nil when we're done processing a key/value pair, then assume
    # the value is a path.
    currentKey = null
    # Current value -- likely just a single string, but perhaps a longer array of strings to be joined with
    # commas.
    currentValue = []
    query = { paths: [] }

    # String trim (could move this to a utility class if it is useful elsewhere).
    trim = (s) -> s.replace(/^\s+|\s+$/g, "")

    emitKeyValue = (key, value) ->

      looksLikeSha = (chunk) ->
        # sha is 40 chars but is usually shortened to 7. Ensure that we don't pick up words by mistake
        # by checking that there is atleast one digit in the chunk.
        return chunk.match(/[0-9a-f]{7,40}/) and chunk.match(/\d/g).length > 0

      if key in ["paths"]
        if (looksLikeSha(value))
          query["sha"] = value
         else
          query.paths.push(value)
      else
        query[key] = value

    # Handle one space-delimited chunk from the search query. We figure out from the previous context how to
    # handle it.
    emitChunk = (chunk) ->
      chunk = trim(chunk)
      return if chunk == ""
      # If we've seen a key, we're just appending (possibly comma-separated) parts.
      if currentKey?
        notLast = chunk[chunk.length - 1] == ","
        currentValue.push(part) for part in chunk.split(",") when part != ""
        return if notLast
        emitKeyValue(currentKey, currentValue.join(","))
        currentKey = null
        currentValue = []
      # Else we're expecting a new chunk (i.e. a search key followed by a colon).
      else
        splitPoint = chunk.indexOf(":")
        switch splitPoint
          when -1 then emitKeyValue("paths", chunk) # Assume it's a path if it's not a key (i.e. no colon).
          when 0 then emitChunk(chunk.slice(1))
          else
            currentKey = chunk.slice(0, splitPoint)
            emitChunk(chunk.slice(splitPoint + 1))

    emitChunk(chunk) for chunk in searchString.split(/\s+/)

    # Take care of un-emmitted key/value pair (this happens when you have a trailing comma).
    if currentKey?
      emitKeyValue(currentKey, currentValue.join(","))

    for synonym, keyword of SYNONYMS
      if query[synonym]?
        query[keyword] ?= query[synonym]
        delete query[synonym]

    query

  search: ->
    queryParams = @parseSearch(@searchBox.val())
    if (queryParams.sha)
      # we are expecting a single commit, just redirect to a new page.
      window.open("/commits/search/by_sha?" + $.param(queryParams))
    else
      $.post("/search", queryParams, (e) => CommitSearch.onSearchSaved e)
