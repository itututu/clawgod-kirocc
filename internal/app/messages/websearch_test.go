package messages

import (
	"bytes"
	"context"
	"encoding/json/v2"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/d-kuro/kirocc/internal/auth"
	"github.com/d-kuro/kirocc/internal/kiroclient"
	"github.com/d-kuro/kirocc/internal/kiroproto"
)

type webSearchTestAuth struct{}

func (webSearchTestAuth) GetToken(context.Context) (*auth.Credentials, error) {
	return &auth.Credentials{
		AccessToken: "access-token",
		ProfileARN:  "arn:test-profile",
		Region:      "us-east-1",
	}, nil
}

type webSearchTestClient struct {
	query string
	calls int
}

func (c *webSearchTestClient) GenerateAssistantResponse(context.Context, string, *kiroproto.Payload, string) (*kiroclient.Response, error) {
	return nil, errors.New("inference endpoint must not be called for native web_search")
}

func (c *webSearchTestClient) SearchWeb(_ context.Context, token, profileARN, region, query string) (*kiroclient.WebSearchResponse, error) {
	c.calls++
	c.query = query
	if token != "access-token" || profileARN != "arn:test-profile" || region != "us-east-1" {
		return nil, errors.New("wrong credentials passed to web search")
	}
	published := int64(1732299319000)
	return &kiroclient.WebSearchResponse{
		Query:        query,
		TotalResults: 1,
		Results: []kiroclient.WebSearchResult{{
			Title:         "Kiro documentation",
			URL:           "https://kiro.dev/docs",
			Snippet:       "Official Kiro documentation.",
			PublishedDate: &published,
		}},
	}, nil
}

func webSearchRequest(t *testing.T, stream bool, tools string) *http.Request {
	t.Helper()
	body := `{
		"model":"claude-sonnet-4-6",
		"max_tokens":1024,
		"stream":` + boolJSON(stream) + `,
		"messages":[{"role":"user","content":"Perform a web search for the query: latest Kiro release"}],
		"tools":` + tools + `,
		"tool_choice":{"type":"tool","name":"web_search"}
	}`
	req := httptest.NewRequest(http.MethodPost, "/v1/messages", bytes.NewBufferString(body))
	req.Header.Set(headerCCSessionID, "session-websearch-test")
	return req
}

func boolJSON(v bool) string {
	if v {
		return "true"
	}
	return "false"
}

const nativeWebSearchToolJSON = `[{"max_uses":8,"type":"web_search_20250305","name":"web_search"}]`

func TestHandleMessagesNativeWebSearchNonStreaming(t *testing.T) {
	client := &webSearchTestClient{}
	service := New(webSearchTestAuth{}, client)
	rec := httptest.NewRecorder()
	service.HandleMessages(rec, webSearchRequest(t, false, nativeWebSearchToolJSON))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", rec.Code, rec.Body.String())
	}
	if client.calls != 1 || client.query != "latest Kiro release" {
		t.Fatalf("search calls=%d query=%q", client.calls, client.query)
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	blocks := resp["content"].([]any)
	if len(blocks) != 3 {
		t.Fatalf("content blocks = %d, want 3", len(blocks))
	}
	serverUse := blocks[0].(map[string]any)
	result := blocks[1].(map[string]any)
	if serverUse["type"] != "server_tool_use" || result["type"] != "web_search_tool_result" {
		t.Fatalf("unexpected block types: %v %v", serverUse["type"], result["type"])
	}
	if serverUse["id"] == "" || result["tool_use_id"] != serverUse["id"] {
		t.Fatalf("tool id mismatch: server=%v result=%v", serverUse["id"], result["tool_use_id"])
	}
	searchContent := result["content"].([]any)[0].(map[string]any)
	if searchContent["url"] != "https://kiro.dev/docs" || searchContent["page_age"] != "November 22, 2024" {
		t.Fatalf("unexpected search result: %+v", searchContent)
	}
	usage := resp["usage"].(map[string]any)
	serverUsage := usage["server_tool_use"].(map[string]any)
	if serverUsage["web_search_requests"] != float64(1) {
		t.Fatalf("server tool usage = %+v", serverUsage)
	}
}

func TestHandleMessagesNativeWebSearchStreamingContract(t *testing.T) {
	client := &webSearchTestClient{}
	service := New(webSearchTestAuth{}, client)
	rec := httptest.NewRecorder()
	service.HandleMessages(rec, webSearchRequest(t, true, nativeWebSearchToolJSON))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", rec.Code, rec.Body.String())
	}
	events := parseSSEData(t, rec.Body.String())
	if len(events) < 10 {
		t.Fatalf("events = %d, body:\n%s", len(events), rec.Body.String())
	}
	if events[0]["type"] != "message_start" || events[len(events)-1]["type"] != "message_stop" {
		t.Fatalf("bad stream boundaries: first=%v last=%v", events[0]["type"], events[len(events)-1]["type"])
	}

	var serverID, resultID string
	var sawInputDelta, sawText, sawServerUsage bool
	for _, event := range events {
		switch event["type"] {
		case "content_block_start":
			block := event["content_block"].(map[string]any)
			switch block["type"] {
			case "server_tool_use":
				serverID, _ = block["id"].(string)
			case "web_search_tool_result":
				resultID, _ = block["tool_use_id"].(string)
			case "text":
				sawText = true
			}
		case "content_block_delta":
			delta := event["delta"].(map[string]any)
			if delta["type"] == "input_json_delta" && strings.Contains(delta["partial_json"].(string), "latest Kiro release") {
				sawInputDelta = true
			}
		case "message_delta":
			usage := event["usage"].(map[string]any)
			serverUsage := usage["server_tool_use"].(map[string]any)
			sawServerUsage = serverUsage["web_search_requests"] == float64(1)
		}
	}
	if serverID == "" || resultID != serverID || !sawInputDelta || !sawText || !sawServerUsage {
		t.Fatalf("contract mismatch serverID=%q resultID=%q inputDelta=%v text=%v usage=%v", serverID, resultID, sawInputDelta, sawText, sawServerUsage)
	}
}

func TestHandleMessagesRejectsMixedNativeWebSearch(t *testing.T) {
	client := &webSearchTestClient{}
	service := New(webSearchTestAuth{}, client)
	rec := httptest.NewRecorder()
	tools := `[{"type":"web_search_20250305","name":"web_search"},{"name":"Bash","input_schema":{"type":"object"}}]`
	service.HandleMessages(rec, webSearchRequest(t, false, tools))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, body=%s", rec.Code, rec.Body.String())
	}
	if client.calls != 0 {
		t.Fatalf("mixed request unexpectedly called MCP %d times", client.calls)
	}
}

func TestHandleCountTokensNativeWebSearch(t *testing.T) {
	client := &webSearchTestClient{}
	service := New(webSearchTestAuth{}, client)
	rec := httptest.NewRecorder()
	req := webSearchRequest(t, false, nativeWebSearchToolJSON)
	service.HandleCountTokens(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["input_tokens"].(float64) <= 0 {
		t.Fatalf("input_tokens = %v, want positive", body["input_tokens"])
	}
	if client.calls != 0 {
		t.Fatalf("count_tokens unexpectedly called MCP %d times", client.calls)
	}
}

func parseSSEData(t *testing.T, body string) []map[string]any {
	t.Helper()
	var events []map[string]any
	for line := range strings.SplitSeq(body, "\n") {
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		var event map[string]any
		if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &event); err != nil {
			t.Fatal(err)
		}
		events = append(events, event)
	}
	return events
}
