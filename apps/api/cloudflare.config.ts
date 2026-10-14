import { bindings, defineConfig } from "cf/config";

// D1 migrations use explicit CLI options: --dir migrations --local for local verification.
export default defineConfig({
	accountId: "REPLACE_WITH_YOUR_ACCOUNT_ID",
	worker: {
		name: "bible-companion",
		compatibilityDate: "2026-10-13",
		compatibilityFlags: [
			"nodejs_compat",
		],
		entrypoint: "src/index.ts",
		workersDev: true,
		previewUrls: false,
		// Free accounts enforce the platform CPU limit; custom limits require Paid.
		observability: {
			enabled: false,
		},
		env: {
			ENVIRONMENT: bindings.text("production"),
			RP_ID: bindings.text("bible-companion.kamesan1577.workers.dev"),
			AUTH_ORIGIN: bindings.text("https://bible-companion.kamesan1577.workers.dev"),
			NATIVE_CALLBACK: bindings.text("biblecompanion://auth/callback"),
			AI_ENABLED: bindings.text("false"),
			DEBUG_ACCOUNT_IDS: bindings.text("[]"),
			CONNECTED_MODELS: bindings.text("[]"),
			DEFAULT_MODEL_ID: bindings.text("@cf/google/gemma-4-26b-a4b-it"),
			DAILY_APP_BUDGET: bindings.text("9000"),
			DAILY_USER_BUDGET: bindings.text("2000"),
			AI_RESERVATION_UNITS: bindings.text("500"),
			TERMS_REVIEWED_MODELS: bindings.text("[]"),
			TERMS_REVIEW_VERSION: bindings.text(""),
			DB: bindings.d1({
				name: "bible-companion",
				id: "REPLACE_WITH_YOUR_D1_DATABASE_ID",
			}),
		},
	},
});
