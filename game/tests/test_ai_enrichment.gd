extends TestCase
## Optional AI enrichment: off without configuration, and with an OpenAI-compatible endpoint
## (a local mock server here) it rewrites only text fields of characters and items.

const PORT := 18766


func test_disabled_without_configuration() -> void:
	var ai := AiEnrichment.new()
	tree.root.add_child(ai)
	ai.endpoint = ""
	var c := {"name": "Test", "bio": "local bio", "traits": []}
	ai.enrich_character(c)
	assert_eq(ai.pending(), 0, "nothing queued when disabled")
	assert_eq(str(c["bio"]), "local bio", "local text untouched")
	ai.queue_free()


func test_rewrites_text_through_endpoint() -> void:
	var pid := OS.create_process("python3", [ProjectSettings.globalize_path("res://tests/mock_ai_server.py"), str(PORT)])
	assert_true(pid > 0, "mock server started")
	await tree.create_timer(0.8).timeout
	var ai := AiEnrichment.new()
	tree.root.add_child(ai)
	ai.endpoint = "http://127.0.0.1:%d/v1/chat/completions" % PORT
	var rng := RngUtil.make([7, "ai-test"])
	var c := NpcGen.generate(rng, {"role": "explorer"})
	var skills_before := JSON.stringify(c["skills"])
	var item := ItemGen.generate(rng, {"level": 2, "quality": "rare"})
	ai.enrich_character(c)
	ai.enrich_item(item)
	var waited := 0.0
	while ai.pending() > 0 and waited < 10.0:
		await tree.create_timer(0.1).timeout
		waited += 0.1
	OS.kill(pid)
	assert_eq(str(c.get("bio", "")), "Mock skies are kinder than they look.", "bio rewritten")
	assert_true(bool(c.get("ai_enriched", false)), "character marked enriched")
	assert_eq(JSON.stringify(c["skills"]), skills_before, "stats untouched")
	assert_eq(str(item.get("flavor", "")), "It remembers every road it has ever travelled.", "item flavor rewritten")
	ai.queue_free()
