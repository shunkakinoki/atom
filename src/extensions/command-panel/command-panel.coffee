{View, $$$} = require 'space-pen'
CommandInterpreter = require 'command-panel/command-interpreter'
RegexAddress = require 'command-panel/commands/regex-address'
CompositeCommand = require 'command-panel/commands/composite-command'
PreviewList = require 'command-panel/preview-list'
Editor = require 'editor'
{SyntaxError} = require('pegjs').parser

_ = require 'underscore'

module.exports =
class CommandPanel extends View
  @activate: (rootView, state) ->
    requireStylesheet 'command-panel.css'
    if state?
      @instance = CommandPanel.deserialize(state, rootView)
    else
      @instance = new CommandPanel(rootView)

  @deactivate: ->
    @instance.detach()

  @serialize: ->
    text: @instance.miniEditor.getText()
    visible: @instance.hasParent()

  @deserialize: (state, rootView) ->
    commandPanel = new CommandPanel(rootView)
    commandPanel.attach(state.text) if state.visible
    commandPanel

  @content: ->
    @div class: 'command-panel', =>
      @subview 'previewList', new PreviewList()
      @div class: 'prompt-and-editor', =>
        @div ':', class: 'prompt', outlet: 'prompt'
        @subview 'miniEditor', new Editor(mini: true)

  commandInterpreter: null
  history: null
  historyIndex: 0

  initialize: (@rootView)->
    @commandInterpreter = new CommandInterpreter(@rootView.project)
    @history = []

    @on 'command-panel:unfocus', => @rootView.focus()
    @rootView.on 'command-panel:toggle', => @toggle()
    @rootView.on 'command-panel:toggle-preview', => @togglePreview()
    @rootView.on 'command-panel:execute', => @execute()
    @rootView.on 'command-panel:find-in-file', => @attach("/")
    @rootView.on 'command-panel:find-in-project', => @attach("Xx/")
    @rootView.on 'command-panel:repeat-relative-address', => @repeatRelativeAddress()
    @rootView.on 'command-panel:repeat-relative-address-in-reverse', => @repeatRelativeAddressInReverse()
    @rootView.on 'command-panel:set-selection-as-regex-address', => @setSelectionAsLastRelativeAddress()

    @miniEditor.off 'move-up move-down'
    @miniEditor.on 'move-up', => @navigateBackwardInHistory()
    @miniEditor.on 'move-down', => @navigateForwardInHistory()

  toggle: ->
    if @miniEditor.isFocused
      @detach()
      @rootView.focus()
    else
      @attach() unless @hasParent()
      @miniEditor.focus()

  togglePreview: ->
    if @previewList.is(':focus')
      @previewList.hide()
      @detach()
      @rootView.focus()
    else
      @attach() unless @hasParent()
      @previewList.show().focus()

  attach: (text='') ->
    @rootView.append(this)
    @miniEditor.focus()
    @miniEditor.setText(text)
    @miniEditor.setCursorBufferPosition([0, Infinity])

  detach: ->
    @rootView.focus()
    @previewList.hide()
    if @previewedOperations
      operation.destroy() for operation in @previewedOperations
      @previewedOperations = undefined
    super

  execute: (command = @miniEditor.getText()) ->
    try
      @commandInterpreter.eval(command, @rootView.getActiveEditSession()).done (operationsToPreview) =>
        @history.push(command)
        @historyIndex = @history.length
        if operationsToPreview?.length
          @populatePreviewList(operationsToPreview)
        else
          @detach()
    catch error
      if error.name is "SyntaxError"
        @flashError()
        return
      else
        throw error

  populatePreviewList: (operations) ->
    @previewedOperations = operations
    @previewList.populate(operations)
    @previewList.focus()

  navigateBackwardInHistory: ->
    return if @historyIndex == 0
    @historyIndex--
    @miniEditor.setText(@history[@historyIndex])

  navigateForwardInHistory: ->
    return if @historyIndex == @history.length
    @historyIndex++
    @miniEditor.setText(@history[@historyIndex] or '')

  repeatRelativeAddress: ->
    @commandInterpreter.repeatRelativeAddress(@rootView.getActiveEditSession())

  repeatRelativeAddressInReverse: ->
    @commandInterpreter.repeatRelativeAddressInReverse(@rootView.getActiveEditSession())

  setSelectionAsLastRelativeAddress: ->
    selection = @rootView.getActiveEditor().getSelectedText()
    regex = _.escapeRegExp(selection)
    @commandInterpreter.lastRelativeAddress = new CompositeCommand([new RegexAddress(regex)])
