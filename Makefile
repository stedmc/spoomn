-include .env
export

# ============================================================
# Setup
# ============================================================

.PHONY: setup
setup: gen

.PHONY: gen
gen:
	cd packages/spoomn_core && dart run build_runner build --delete-conflicting-outputs
	cd packages/spoomn_client && dart run build_runner build --delete-conflicting-outputs

# ============================================================
# Database
# ============================================================

.PHONY: db-start
db-start:
	supabase start

.PHONY: db-stop
db-stop:
	supabase stop

.PHONY: db-status
db-status:
	supabase status

.PHONY: db-migrate
db-migrate:
	supabase db push

.PHONY: db-reset
db-reset:
	supabase db reset

# ============================================================
# Server
# ============================================================

.PHONY: server
server:
	cd packages/spoomn_server && \
		SUPABASE_URL=$(SUPABASE_URL) \
		SUPABASE_SERVICE_ROLE_KEY=$(SUPABASE_SERVICE_ROLE_KEY) \
		PORT=$(PORT) \
		dart run bin/server.dart

# ============================================================
# Client
# ============================================================

.PHONY: client
client:
	cd packages/spoomn_client && flutter run -d chrome \
		--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
		--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
		--dart-define=SERVER_URL=$(SERVER_URL)

# Run two browser windows for local multiplayer testing
.PHONY: client2
client2:
	cd packages/spoomn_client && flutter run -d chrome \
		--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
		--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
		--dart-define=SERVER_URL=$(SERVER_URL) \
		--web-port=3001 &
	cd packages/spoomn_client && flutter run -d chrome \
		--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
		--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
		--dart-define=SERVER_URL=$(SERVER_URL) \
		--web-port=3002
