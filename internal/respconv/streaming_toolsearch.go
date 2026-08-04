package respconv

// Modified by ClaudeCode Kiro to emit native WebSearch SSE blocks.

import (
	"github.com/d-kuro/kirocc/internal/anthropic"
	"github.com/d-kuro/kirocc/internal/toolsearch"
)

// WriteServerToolUse writes a server_tool_use content block start + input delta + stop.
func (s *SSEWriter) WriteServerToolUse(id, name, input string) {
	s.ensureStarted()
	s.fireVisibleOutput()
	s.writeBlock(
		map[string]any{
			"type":  anthropic.BlockTypeServerToolUse,
			"id":    id,
			"name":  name,
			"input": map[string]any{},
		},
		map[string]any{
			"type":         "input_json_delta",
			"partial_json": input,
		},
	)
}

// WriteToolSearchResult writes a tool_search_tool_result content block.
func (s *SSEWriter) WriteToolSearchResult(toolUseID string, toolRefs []string) {
	s.writeBlock(
		map[string]any{
			"type":        anthropic.BlockTypeToolSearchToolResult,
			"tool_use_id": toolUseID,
			"content": map[string]any{
				"type":            anthropic.BlockTypeToolSearchSearchResult,
				"tool_references": toolsearch.ToolRefMaps(toolRefs),
			},
		},
		nil,
	)
}

// WriteToolSearchError writes a tool_search_tool_result error content block.
func (s *SSEWriter) WriteToolSearchError(toolUseID string, errorCode string) {
	s.writeBlock(
		map[string]any{
			"type":        anthropic.BlockTypeToolSearchToolResult,
			"tool_use_id": toolUseID,
			"content": map[string]any{
				"type":       anthropic.BlockTypeToolSearchResultError,
				"error_code": errorCode,
			},
		},
		nil,
	)
}

// WriteWebSearchResult writes an Anthropic native web_search_tool_result block.
func (s *SSEWriter) WriteWebSearchResult(toolUseID string, content []map[string]any) {
	s.writeBlock(
		map[string]any{
			"type":        anthropic.BlockTypeWebSearchToolResult,
			"tool_use_id": toolUseID,
			"content":     content,
		},
		nil,
	)
}

// WriteText writes one complete visible text delta.
func (s *SSEWriter) WriteText(text string) {
	if text == "" {
		return
	}
	s.ensureStarted()
	s.fireVisibleOutput()
	s.switchBlock(anthropic.BlockTypeText)
	s.writeDelta("text_delta", "text", text)
}

// FinishWebSearch closes a synthetic native web-search stream with explicit
// usage, including Anthropic's server tool accounting extension.
func (s *SSEWriter) FinishWebSearch(inputTokens, outputTokens int) error {
	s.ensureStarted()
	s.closeActiveBlock()
	s.writeSSE("message_delta", map[string]any{
		"type": "message_delta",
		"delta": map[string]any{
			"stop_reason":   "end_turn",
			"stop_sequence": nil,
		},
		"usage": map[string]any{
			"input_tokens":                inputTokens,
			"output_tokens":               outputTokens,
			"cache_read_input_tokens":     0,
			"cache_creation_input_tokens": 0,
			"server_tool_use": map[string]any{
				"web_search_requests": 1,
			},
		},
	})
	s.writeSSE("message_stop", map[string]any{"type": "message_stop"})
	return s.writeErr
}
