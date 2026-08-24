
---@class PiDiagnostic
---@field message string
---@field severity number
---@field lnum number
---@field col number
---@field end_lnum? number
---@field end_col? number
---@field source? string
---@field code? string|number
---@field user_data? any

---@class PiConfigFile
---@field theme string
---@field autoshare boolean
---@field autoupdate boolean
---@field model string
---@field agent table<string, table>
---@field mcp table<string, table>
---@field mode table<string, table>
---@field command table<string, table>
---@field plugin table[]
---@field username string

---@class PiProject
---@field id string
---@field worktree string
---@field vcs string
---@field time { created: number }

---@class PiPath
---@field state string
---@field config string
---@field worktree string
---@field directory string

---@class PiSkill
---@field name string
---@field description string|nil
---@field location string
---@field content string

---@class PiCommand
---@field description string
---@field agent string
---@field model string
---@field template string

---@class PiUICommand
---@field desc string
---@field execute fun(args: string[], range: PiSelectionRange|nil): any
---@field completions? string[]
---@field nested_subcommand? PiNestedSubcommandValidation
---@field completion_provider_id? string
---@field sub_completions? string[]
---@field nargs? string|integer
---@field range? boolean
---@field complete? boolean

---@class PiNestedSubcommandValidation
---@field allow_empty boolean

---@class PiCommandSubcommandSpec
---@field completions? string[]
---@field nested_subcommand? PiNestedSubcommandValidation
---@field sub_completions? string[]
---@field completion_provider_id? string

---@class PiCommandApi
---@field [string] any

---@alias PiCommandHandler fun(api: PiCommandApi, args: string[], range?: PiSelectionRange): any
---@alias PiCommandHandlerMap table<string, PiCommandHandler>

---@class PiParsedIntentSource
---@field raw_args string
---@field argv string[]

---@class PiParsedIntent
---@field name string
---@field hook_key? string
---@field args string[]
---@field range PiSelectionRange|nil
---@field source PiParsedIntentSource

---@class PiCommandParseError
---@field code 'unknown_subcommand'|'invalid_subcommand'
---@field message string
---@field subcommand string

---@class PiCommandParseResult
---@field ok boolean
---@field intent? PiParsedIntent
---@field error? PiCommandParseError

---@class PiCommandRouteOpts
---@field args? string
---@field range? integer
---@field line1? integer
---@field line2? integer

---@class PiCommandDispatchError
---@field code 'unknown_subcommand'|'missing_handler'|'missing_execute'|'invalid_subcommand'|'invalid_arguments'|'execute_error'
---@field message string
---@field subcommand? string

---@class PiCommandDispatchResult
---@field ok boolean
---@field intent? PiParsedIntent
---@field result? any
---@field error? PiCommandDispatchError

---@class PiCommandActionContext
---@field parsed PiCommandParseResult
---@field intent? PiParsedIntent
---@field args? string[]
---@field range? PiSelectionRange|nil
---@field execute? fun(args: string[], range: PiSelectionRange|nil): any

---@class SessionRevertInfo
---@field messageID string
---@field partID? string
---@field snapshot string
---@field diff string

---@class SessionShareInfo
---@field url string

---@class Session
---@field workspace string
---@field title string
---@field time { created: number, updated: number }
---@field id string
---@field parentID string|nil
---@field agent string|nil
---@field model { id: string, providerID: string, variant?: string }|nil
---@field directory? string
---@field revert? SessionRevertInfo
---@field share? SessionShareInfo

---@class SessionProjectInfo
---@field id string
---@field name? string
---@field worktree string

---@class GlobalSession : Session
---@field project SessionProjectInfo|nil

---@class PiKeymapEntry
---@field [1] string # Function name
---@field mode? string|string[] # Mode(s) for the keymap
---@field desc? string # Keymap description
---@field defer_to_completion? boolean # Whether to defer the keymap when completion menu is open

---@class PiKeymapEditor : table<string, PiKeymapEntry>
---@class PiKeymapInputWindow : table<string, PiKeymapEntry>
---@class PiKeymapOutputWindow : table<string, PiKeymapEntry>

---@class PiKeymap
---@field editor PiKeymapEditor
---@field input_window PiKeymapInputWindow
---@field output_window PiKeymapOutputWindow
---@field session_picker PiSessionPickerKeymap
---@field timeline_picker PiTimelinePickerKeymap
---@field history_picker PiHistoryPickerKeymap
---@field quick_chat PiQuickChatKeymap

---@class PiSessionPickerKeymap
---@field delete_session PiKeymapEntry
---@field new_session PiKeymapEntry
---@field rename_session PiKeymapEntry
---@field fork_session PiKeymapEntry
---@field toggle_scope PiKeymapEntry

---@class PiTimelinePickerKeymap
---@field undo PiKeymapEntry
---@field fork PiKeymapEntry

---@class PiHistoryPickerKeymap
---@field delete_entry PiKeymapEntry
---@field clear_all PiKeymapEntry

---@class PiQuickChatKeymap
---@field cancel PiKeymapEntry

---@class PiCompletionFileSourcesConfig
---@field enabled boolean
---@field preferred_cli_tool 'server'|'fd'|'fdfind'|'rg'|'git'
---@field ignore_patterns string[]
---@field max_files number
---@field max_display_length number

---@class PiCompletionConfig
---@field file_sources PiCompletionFileSourcesConfig

---@class PiLoadingAnimationConfig
---@field frames string[]

---@class PiServerConfig
---@field url string | nil -- URL/hostname of custom pi server (e.g., "http://192.168.1.100" or "localhost")
---@field port number | 'auto' | nil -- Port number, 'auto' for random, or nil for default (4096)
---@field timeout number -- Timeout in seconds for health check (default: 5)
---@field retry_delay number -- Delay in milliseconds between health check retries (default: 2000)
---@field spawn_command? fun(port: number, url: string): number | nil -- Optional function to start the server, may return server PID
---@field kill_command? fun(port: number, url: string): nil -- Optional function to stop the server when auto_kill is true
---@field auto_kill boolean -- Kill spawned servers when nvim exits (default: true)
---@field path_map (string | fun(host_path: string): string) | nil -- Map host paths to server paths
---@field reverse_path_map (fun(server_path: string): string) | nil -- Map server paths back to host paths
---@field username? string | fun(): string | nil -- Username for Basic auth. Falls back to PI_SERVER_USERNAME env var, then "pi"
---@field password? string | fun(): string | nil -- Password for Basic auth. Falls back to PI_SERVER_PASSWORD env var

---@class PiUIFloatConfig
---@field width number # Width in columns, or ratio when <= 1 (default: 0.95)
---@field height number # Height in rows, or ratio when <= 1 (default: 0.9)
---@field row number|nil # Top row, centered when nil
---@field col number|nil # Left column, centered when nil
---@field border string|string[]|nil # Float border passed to nvim_open_win
---@field gap integer # Rows between output and input floats
---@field zindex integer # Output float zindex; input uses zindex + 1
---@field opts table<string, any> # Window-local options applied to float windows

---@class PiUIConfig
---@field enable_treesitter_markdown boolean
---@field position 'right'|'left'|'current'|'float' # Position of the UI (default: 'right')
---@field input_position 'bottom'|'top' # Position of the input window (default: 'bottom')
---@field window_width number
---@field persist_state boolean
---@field zoom_width number
---@field float PiUIFloatConfig
---@field picker_width number|false|nil # Width for pickers. 0<w<=1 = fraction of screen; >1 = absolute columns; false = use picker backend defaults.
---@field display_model boolean
---@field display_context_size boolean
---@field display_cost boolean
---@field window_highlight string
---@field icons { preset: 'text'|'nerdfonts', overrides: table<string,string> }
---@field loading_animation PiLoadingAnimationConfig
---@field output PiUIOutputConfig
---@field input PiUIInputConfig
---@field completion PiCompletionConfig
---@field highlights? PiHighlightConfig
---@field picker PiUIPickerConfig

---Window-local options applied to the input window.
---Any valid Neovim window-local option (`:h window-variable`) can be set here.
---Common examples:
---  signcolumn = 'no'
---  cursorline = true
---  number = true
---  relativenumber = true
---  foldcolumn = '0'
---  statuscolumn = ''
---  conceallevel = 2
---@class PiUIInputWinOptions : table<string, any>
---@field signcolumn? string # Value for 'signcolumn' (e.g. 'yes', 'no', 'auto')
---@field cursorline? boolean
---@field number? boolean
---@field relativenumber? boolean

---@class PiUIInputConfig
---@field text { wrap: boolean }
---@field min_height number
---@field max_height number
---@field auto_hide boolean
---@field win_options? PiUIInputWinOptions # Window-local options applied to the input window. Any valid Neovim window option is accepted.

---@class PiHighlightConfig
---@field vertical_borders? { tool?: { fg?: string, bg?: string }, user?: { fg?: string, bg?: string }, assistant?: { fg?: string, bg?: string } }

---@class PiUIOutputRenderingConfig
---@field markdown_debounce_ms number
---@field on_data_rendered (fun(buf: integer, win: integer)|boolean)|nil
---@field markdown_on_idle boolean
---@field event_throttle_ms number
---@field event_collapsing boolean

---@class PiUIOutputToolsConfig
---@field show_output boolean
---@field show_reasoning_output boolean
---@field use_folds boolean
---@field fold_exclude (string|{server: string, tool: string})[]|nil
---@field folding_threshold number

---@class PiUIOutputConfig
---@field time_format string|nil # Custom os.date format for timestamps, e.g. '%m/%d %H:%M'. Uses fixed default when nil.
---@field tools PiUIOutputToolsConfig
---@field rendering PiUIOutputRenderingConfig
---@field max_messages integer|nil
---@field always_scroll_to_bottom boolean
---@field filetype string
---@field compact_assistant_headers boolean | 'minimal' | 'hidden' | 'full'

---@class PiUIPickerConfig
---@field snacks_layout? snacks.picker.layout.Config
--- TODO: add more picker-specific presets

---@class PiContextConfig
---@field enabled boolean
---@field cursor_data { enabled: boolean, context_lines?: number }
---@field diagnostics { enabled:boolean, info: boolean, warning: boolean, error: boolean, only_closest: boolean}
---@field current_file { enabled: boolean }
---@field selection { enabled: boolean }
---@field agents { enabled: boolean }
---@field buffer { enabled: boolean }
---@field git_diff { enabled: boolean }

---@alias PiToggleableContextKey
---| 'current_file'
---| 'selection'
---| 'diagnostics'
---| 'cursor_data'
---| 'buffer'
---| 'git_diff'

---@class PiDebugConfig
---@field enabled boolean
---@field capture_streamed_events boolean
---@field show_ids boolean
---@field highlight_changed_lines boolean
---@field highlight_changed_lines_timeout_ms integer
---@field quick_chat {keep_session: boolean, set_active_session: boolean}

---@alias PiCommandLifecycleStage 'before'|'after'|'error'|'finally'
---@alias PiCommandDispatchHook fun(ctx: PiCommandDispatchContext): PiCommandDispatchContext|nil
---@alias PiCommandHookScope string|string[]|'*'

---@class PiCommandHookRegisterOptions
---@field command? PiCommandHookScope

---@class PiHooks
---@field on_file_edited? fun(file: string): nil
---@field on_session_loaded? fun(session: Session): nil
---@field on_done_thinking? fun(session: Session): nil
---@field on_permission_requested? fun(session: Session): nil
---@field on_command_before? PiCommandDispatchHook
---@field on_command_after? PiCommandDispatchHook
---@field on_command_error? PiCommandDispatchHook
---@field on_command_finally? PiCommandDispatchHook

---@class PiCommandDispatchContext
---@field parsed PiCommandParseResult
---@field intent PiParsedIntent|nil
---@field args string[]|nil
---@field range PiSelectionRange|nil
---@field result? any
---@field error PiCommandDispatchError|nil

---@class PiCommandLifecycleHookSpec
---@field before? PiCommandDispatchHook
---@field after? PiCommandDispatchHook
---@field error? PiCommandDispatchHook
---@field finally? PiCommandDispatchHook
---@field on_command_before? PiCommandDispatchHook
---@field on_command_after? PiCommandDispatchHook
---@field on_command_error? PiCommandDispatchHook
---@field on_command_finally? PiCommandDispatchHook

---@class PiProviders
---@field [string] string[]

---@class PiConfigModule
---@field defaults PiConfig
---@field values PiConfig
---@field setup fun(opts?: PiConfig): nil
---@field get_key_for_function fun(scope: 'editor'|'input_window'|'output_window', function_name: string): string|nil

---@class PiQuickChatConfig
---@field default_model? string -- Use current model if nil
---@field default_agent? string -- Use current mode if nil
---@field instructions? string[] -- Custom instructions for quick chat

---@class PiLoggingConfig
---@field enabled boolean
---@field level 'debug' | 'info' | 'warn' | 'error'
---@field outfile string|nil

---@class PiSlashCommandSpec
---@field desc? string
---@field args? boolean
---@field cmd_str? string
---@field command_name? string
---@field preset_args? string[]
---@field fn? fun(args:string[]|nil):nil|Promise<any>|any

---@class PiConfig
---@field preferred_picker 'telescope' | 'telescope.nvim' | 'fzf' | 'fzf-lua' | 'mini.pick' | 'snacks' | 'snacks.nvim' | 'select' | nil
---@field default_global_keymaps boolean
---@field default_mode 'build' | 'plan' | string -- Default mode
---@field default_system_prompt string | nil
---@field keymap_prefix string
---@field pi_executable 'pi' | string -- Command run for calling pi
---@field lock_session_to_directory boolean -- If true, active session is preserved across DirChanged events
---@field server PiServerConfig -- Custom/external server configuration
---@field keymap PiKeymap
---@field ui PiUIConfig
---@field context PiContextConfig
---@field logging PiLoggingConfig
---@field debug PiDebugConfig
---@field prompt_guard? fun(mentioned_files: string[]): boolean
---@field child_readonly boolean
---@field hooks PiHooks
---@field quick_chat PiQuickChatConfig
---@field snapshot_path? string -- Override base path for snapshot storage (default: $XDG_DATA_HOME/pi). Appends /snapshot/<project_id>/<worktree_hash>

---@class MessagePartState
---@field input TaskToolInput|BashToolInput|FileToolInput|TodoToolInput|GlobToolInput|GrepToolInput|WebFetchToolInput|ListToolInput|QuestionToolInput|ApplyPatchToolInput Input data for the tool
---@field metadata TaskToolMetadata|ToolMetadataBase|WebFetchToolMetadata|BashToolMetadata|FileToolMetadata|GlobToolMetadata|GrepToolMetadata|ListToolMetadata|QuestionToolMetadata Metadata about the tool execution
---@field time { start: number, end: number } Timestamps for tool use
---@field status string Status of the tool use (e.g., 'running', 'completed', 'failed')
---@field title string Title of the tool use
---@field output string Output of the tool use, if applicable
---@field error? string Error message if the part failed

---@class ApplyPatchToolInput
---@field patchText string The patch content in unified diff format

---@class ApplyPatchFileResult
---@field filePath string Absolute path to the file
---@field relativePath string Relative path to the file
---@field before string File contents before the patch
---@field after string File contents after the patch
---@field additions number Number of lines added
---@field deletions number Number of lines deleted
---@field type 'add'|'edit'|'delete' Type of file operation
---@field diff string Unified diff for this file

---@class ApplyPatchToolMetadata: ToolMetadataBase
---@field truncated boolean Whether the output was truncated
---@field diagnostics table<string, any> Diagnostic information keyed by file path
---@field files ApplyPatchFileResult[] Per-file results
---@field diff string Combined unified diff for all files

---@class ToolMetadataBase
---@field error boolean|nil Whether the tool execution resulted in an error
---@field message string|nil Optional status or error message

---@class TaskToolMetadata: ToolMetadataBase
---@field summary TaskToolSummaryItem[]
---@field sessionId string|nil Child session ID

---@class WebFetchToolMetadata: ToolMetadataBase
---@field http_status number|nil HTTP response status code
---@field content_type string|nil Content type of the response

---@class BashToolMetadata: ToolMetadataBase
---@field output string|nil

---@class FileToolMetadata: ToolMetadataBase
---@field diff string|nil The diff of changes made to the file
---@field file_type string|nil Detected file type/extension
---@field line_count number|nil Number of lines in the file

---@class GlobToolMetadata: ToolMetadataBase
---@field truncated boolean|nil
---@field count number|nil

---@class GrepToolMetadata: ToolMetadataBase
---@field truncated boolean|nil
---@field matches number|nil

---@class BashToolInput
---@field command string The command to execute
---@field description string Description of what the command does

---@class FileToolInput
---@field filePath string The path to the file
---@field content? string Content to write (for write tool)

---@class TodoToolInput
---@field todos { id: string, content: string, status: 'pending'|'in_progress'|'completed'|'cancelled', priority: 'high'|'medium'|'low' }[]

---@class ListToolInput
---@field path string The directory path to list

---@class ListToolMetadata: ToolMetadataBase
---@field truncated boolean|nil
---@field count number|nil

---@class GlobToolInput
---@field pattern string The glob pattern to match files against
---@field path? string Optional directory to search in

---@class ListToolOutput
---@field output string The raw output string from the list tool

---@class GrepToolInput
---@field pattern? string The glob pattern to match
---@field path? string Optional directory to search in
---@field include? string Optional file type to include (e.g., '*.lua')

---@class WebFetchToolInput
---@field url string The URL to fetch content from
---@field format 'text'|'markdown'|'html'
---@field timeout? number Optional timeout in seconds (max 120)

---@class TaskToolInput
---@field prompt string The subtask prompt
---@field description string Description of the subtask
---@field subagent_type string The type of specialized agent to use

---@class TaskToolSummaryItem
---@field id string Tool call ID
---@field tool string Tool name
---@field state { status: string, title?: string }

-- Question types

---@class PiQuestionOption
---@field label string Display text
---@field description string Explanation of choice

---@class PiQuestionInfo
---@field question string Complete question
---@field header string Very short label (max 12 chars)
---@field options PiQuestionOption[] Available choices
---@field multiple? boolean Allow selecting multiple choices
---@field custom? boolean Allow a custom response

---@class PiQuestionRequest
---@field id string Question request ID
---@field sessionID string Session ID
---@field questions PiQuestionInfo[] Questions to ask
---@field tool? { messageID: string, callID: string }

---@class QuestionToolInput
---@field questions PiQuestionInfo[] Questions that were asked

---@class QuestionToolMetadata: ToolMetadataBase
---@field answers string[][] Array of answer arrays (one per question)
---@field truncated boolean Whether the results were truncated

---@class MessageTokenCount
---@field reasoning number
---@field input number
---@field output number
---@field cache { write: number, read: number }

---@class OutputMetadata
---@field msg_idx number|nil Message index in session
---@field part_idx number|nil Part index in message
---@field role 'user'|'assistant'|'system'|nil Message role
---@field type 'text'|'tool'|'header'|'patch'|'step-start'|nil Message part type
---@field snapshot? string|nil snapshot commit hash

---@class OutputAction
---@field text string Action text
---@field type 'diff_revert_all'|'diff_revert_selected_file'|'diff_open'|'diff_restore_snapshot_file'|'diff_restore_snapshot_all'|'navigate_session_tree'|'toggle_max_messages'|'undo'|'copy_message'|'fork_session'
---@field args? string[] Optional arguments for the command
---@field key string keybinding for the action
---@field display_line number Line number to display the action
---@field range? { from: number, to: number } Optional range for the action

---@class CodeReferenceTextRange
---@field start_offset integer Raw part text offset, 1-based inclusive
---@field end_offset integer Raw part text offset, 1-based inclusive

---@class CodeReference
---@field session_id string
---@field message_id string
---@field part_id string
---@field path string
---@field line? integer
---@field col? integer
---@field source_kind 'assistant_text'|'tool_file_path'
---@field raw_range? CodeReferenceTextRange Required for assistant_text references
---@field order integer Smaller values appear earlier in the session message/part/text order.

---@class SymbolSnapshotCycle

---@class FormatterContext
---@field interactive boolean
---@field get_child_parts? fun(session_id: string): PiMessagePart[]?
---@field current_refs? CodeReference[]
---@field current_files? string[]
---@field symbol_cycle? SymbolSnapshotCycle

---@class OutputTargetRange
---@field line integer Output-local line, 1-based
---@field start_col integer Output-local column, 0-based inclusive
---@field end_col integer Output-local column, 0-based exclusive

---@class OutputTarget
---@field kind 'file'|'diff'|'symbol'
---@field range OutputTargetRange
---@field path? string
---@field line? integer
---@field col? integer
---@field token? string
---@field candidate_files? string[]

---@class RenderedTarget: OutputTarget
---@field part_id string
---@field message_id string

---@alias OutputExtmarkType vim.api.keyset.set_extmark & {start_col:0}
---@alias OutputExtmark OutputExtmarkType|fun():OutputExtmarkType

---@class PiMessage
---@field info MessageInfo Metadata about the message
---@field parts PiMessagePart[] Parts that make up the message
---@field references CodeReference[]|nil Parsed file references from text parts (cached)
---@field system string|nil System message content

---@class MessageInfo
---@field id string Unique message identifier
---@field sessionID string Unique session identifier
---@field tokens MessageTokenCount Token usage statistics
---@field system string[] System messages
---@field time { created: number, completed: number } Timestamps
---@field cost number Cost of the message
---@field path { cwd: string, root: string } Working directory paths
---@field modelID string Model identifier
---@field providerID string Provider identifier
---@field role 'user'|'assistant'|'system' Role of the message sender
---@field system_role string|nil Role defined in system messages
---@field mode string|nil Agent or mode identifier
---@field error table

---@class RestorePoint
---@field id string Unique restore point identifier
---@field from_snapshot_id string|nil ID of the snapshot this restore point is based on
---@field files string[] List of file paths included in the restore point
---@field deleted_files string[] List of files that were deleted in this restore point
---@field created_at number Timestamp when the restore point was created

---@class PiSnapshotPatch
---@field hash string Unique identifier for the snapshot
---@field files string[] List of file paths included in the snapshot

---@class OpenOpts
---@field focus? 'input' | 'output'
---@field start_insert? boolean
---@field new_session? boolean
---@field open_action? 'reuse_visible'|'restore_hidden'|'create_fresh'

---@class SendMessageOpts
---@field new_session? boolean
---@field context? PiContextConfig
---@field model? string
---@field agent? string
---@field variant? string
---@field system? string

---@class CompletionContext
---@field trigger_char string The character that triggered completion
---@field input string The current input text
---@field cursor_pos number Current cursor position
---@field line string The full current line text

---@class CompletionItem
---@field label string Display text for the completion item
---@field kind string Type of completion item (e.g., 'file', 'subagent')
---@field kind_icon string Icon representing the kind
---@field kind_hl? string Highlight group for the kind
---@field detail string Additional detail text
---@field documentation string Documentation text
---@field insert_text string Text to insert when selected
---@field source_name string Name of the completion source
---@field priority? number Optional priority for individual item sorting (lower numbers have higher priority)
---@field data table Additional data associated with the item

---@class CompletionSource
---@field name string Name of the completion source
---@field priority number Priority for ordering sources
---@field complete fun(context: CompletionContext): Promise<CompletionItem[]> Function to generate completion items
---@field on_complete fun(item: CompletionItem): nil Optional callback when item is selected
---@field is_incomplete? boolean Whether the completion results are incomplete (for sources that support pagination)
---@field get_trigger_character? fun(): string|nil Optional function returning the trigger character for this source
---@field custom_kind? integer Custom LSP CompletionItemKind registered for this source

---Extended LSP completion item with pi-specific rendering fields
---@class PiLspItem : lsp.CompletionItem
---@field kind lsp.CompletionItemKind
---@field kind_hl? string Highlight group for the kind icon
---@field kind_icon string Icon string for the kind

---@class PiContext
---@field current_file PiContextFile|nil
---@field cursor_data PiContextCursorData|nil
---@field mentioned_files string[]|nil
---@field mentioned_subagents string[]|nil
---@field selections PiContextSelection[]|nil
---@field linter_errors PiDiagnostic[]|nil

---@class PiContextSelection
---@field file PiContextFile
---@field content string|nil
---@field lines string|nil

---@class PiContextCursorData
---@field line number
---@field column number
---@field line_content string
---@field lines_before string[]
---@field lines_after string[]

---@class PiContextFile
---@field path string
---@field name string
---@field extension string
---@field sent_at? number

---@class PiMessagePartSourceText
---@field start number
---@field value string
---@field ['end'] number

---@class PiMessagePartSource
---@field path string|nil
---@field type string|nil
---@field text PiMessagePartSourceText|nil
---@field value string|nil

---@class PiMessagePart
---@field type 'text'|'file'|'agent'|'tool'|'step-start'|'patch'|'reasoning'|string
---@field id string|nil Unique identifier for tool use parts
---@field text string|nil
---@field tool string|nil Name of the tool being used
---@field state MessagePartState|nil State information for tool use parts
---@field filename string|nil
---@field mime string|nil
---@field url string|nil
---@field source PiMessagePartSource|nil
---@field name string|nil
---@field synthetic boolean|nil
---@field snapshot string|nil Snapshot commit hash
---@field sessionID string|nil Session identifier
---@field messageID string|nil Message identifier
---@field callID string|nil Call identifier (used for tools)
---@field hash string|nil Hash identifier for patch parts
---@field files string[]|nil List of file paths for patch parts
---@field time { start: number, end?: number }|nil Timestamps for the part

---@class PiModelModalities
---@field input ('text'|'image'|'audio'|'video')[] Supported input modalities
---@field output ('text')[] Supported output modalities

---@class PiModelCost
---@field input number Cost per input token
---@field output number Cost per output token
---@field cache_read number|nil Cost per cache read token
---@field cache_write number|nil Cost per cache write token

---@class PiModelLimits
---@field context number Maximum context length in tokens
---@field output number Maximum output length in tokens

---@class PiModelVariant
---@field reasoningEffort string Reasoning effort level (e.g., "low", "medium", "high")

---@class PiModel
---@field id string Unique identifier for the model
---@field name string Human-readable name of the model
---@field attachment boolean Whether the model supports file attachments
---@field reasoning boolean Whether the model supports reasoning/thinking
---@field temperature boolean Whether the model supports temperature parameter
---@field tool_call boolean Whether the model supports tool calling
---@field knowledge string|nil Knowledge cutoff date (e.g., "2024-04")
---@field release_date string Release date in YYYY-MM-DD format
---@field last_updated string Last updated date in YYYY-MM-DD format
---@field modalities PiModelModalities Supported input/output modalities
---@field open_weights boolean Whether the model has open weights
---@field limit PiModelLimits Token limits for the model
---@field cost PiModelCost Pricing information for the model
---@field variants table<string, PiModelVariant>|nil Model variants with different configurations

---@class PiProvider
---@field id string Unique identifier for the provider
---@field env string[] Required environment variables for authentication
---@field npm string NPM package name for the provider SDK
---@field api string|nil Base API URL for the provider
---@field name string Human-readable name of the provider
---@field doc string|nil Documentation URL for the provider
---@field models table<string, PiModel> Map of model ID to model configuration

---@class PiProvidersResponse
---@field providers PiProvider[] List of available providers
---@field default table<string, string> Map of provider ID to default model ID

---@class PiToolListItem
---@field id string Tool identifier
---@field description string Tool description
---@field parameters any JSON schema parameters for the tool

---@alias PiToolList PiToolListItem[]

---@class PiAgentPermissionBash
---@field [string] string Permission level ('allow', 'deny', etc.)

---@class PiAgentPermission
---@field edit string Permission level for edit operations
---@field webfetch string Permission level for web fetch operations
---@field bash PiAgentPermissionBash Bash command permissions

---@class PiAgentModel
---@field providerID string Provider identifier
---@field modelID string Model identifier

---@class PiAgent
---@field name string Unique identifier for the agent
---@field description string Human-readable description of the agent
---@field tools table<string, boolean> Map of tool names to availability
---@field options table Additional configuration options
---@field permission PiAgentPermission Permissions for various operations
---@field mode 'primary'|'subagent'|'all' Agent execution mode
---@field builtIn boolean Whether this is a built-in agent
---@field model PiAgentModel|nil Optional model configuration
---@field prompt string|nil Optional custom prompt for the agent
---@field temperature number|nil Optional temperature setting

---@class PiSlashCommand
---@field slash_cmd string The command trigger (e.g., "/help")
---@field desc string|nil Description of the command
---@field fn fun(args:string[]|nil):nil|Promise<any>|any Function to execute the command
---@field args boolean Whether the command accepts arguments

---@class PiRevertSummary
---@field messages number Number of messages reverted
---@field tool_calls number Number of tool calls reverted
---@field files table<string, {additions: number, deletions: number}> Summary of file changes reverted

---@class PiSelectionRange
---@field start number Starting line number (inclusive)
---@field stop number Ending line number (inclusive)

---@class PiSessionStatusInfo
---@field type 'idle'|'busy'|'retry' Current status of the session
---@field message? string Human-readable detail (populated for `retry`)
---@field attempt? number Retry attempt counter (populated for `retry`)
---@field next? number Server-side timestamp of the next retry (populated for `retry`)
---@field action? table Optional retry action metadata (populated for `retry`)
