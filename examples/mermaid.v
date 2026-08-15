module main

import vmarkdown

fn main() {
	markdown := '## Mermaid Demo\n\n```mermaid\nflowchart TD\nA[Start] --> B[Parse] & C[Validate]\nB[Parse] --> D[Done]\nC[Validate] --> D[Done]\n```\n\n```mermaid\nsequenceDiagram\nparticipant Alice\nparticipant Bob\nalt hit\nAlice->>Bob: ok\nelse miss\nBob->>Bob: cache\nend\n```\n\n```mermaid\nstateDiagram-v2\n[*] --> Idle\nIdle --> Running: start\nRunning --> [*]: done\n```\n\n```mermaid\nclassDiagram\nclass Animal {\n+name string\n+speak()\n}\nAnimal <|-- Dog : inherits\n```\n\n```mermaid\nerDiagram\nUSER {\nstring id\nstring email\n}\nORDER {\nstring id\n}\nUSER ||--o{ ORDER : places\n```\n\n```mermaid\ngantt\ntitle Release Plan\nsection Build\nCompile :done, a1, 2026-04-01, 1d\nShip :active, after a1, 2d\n```\n\n```mermaid\nmindmap\n  Root\n    Origins\n      History\n      Influences\n    Products\n      Parser\n      Preview\n```\n\n```mermaid\njourney\ntitle User Journey\nsection Morning\nLogin: 5: User\nPay: 3: User, System\n```\n\n```mermaid\ngitGraph\ncommit id: "Init"\nbranch feature\ncheckout feature\ncommit id: "Work"\ncheckout main\nmerge feature\n```\n\n```mermaid\ntimeline\ntitle Product History\n2024 : Parser\n     : Preview\n2025 : Mermaid\n```\n'
	doc := vmarkdown.parse(markdown) or {
		eprintln(err)
		return
	}
	println(doc.to_terminal())
}
