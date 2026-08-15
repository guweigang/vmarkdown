module vmarkdown

fn test_decode_diagram_document_uses_kind_field() {
	raw := '{
  "version": 1,
  "kind": "timeline",
  "entries": [
    { "point": "2024", "text": "Parser" }
  ]
}'
	payload := decode_diagram_document(raw) or { panic(err) }
	match payload {
		DiagramTimeline {
			assert payload.entries.len == 1
			assert payload.entries[0].point == '2024'
			assert payload.entries[0].text == 'Parser'
		}
		else {
			assert false
		}
	}
}

fn test_validate_diagram_document_requires_kind() {
	raw := '{
  "version": 1,
  "entries": [
    { "point": "2024", "text": "Parser" }
  ]
}'
	if _ := validate_diagram_document_raw(raw) {
		assert false
	} else {
		assert err.msg() == 'diagram.kind cannot be empty'
	}
}
