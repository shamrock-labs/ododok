# ODO-157 account-scoped chew profile cache implementation plan

**Goal:** Sync the authenticated user's current profile into an account/model-scoped cache, apply a frozen snapshot to DSP at meal start, and upload its profile ID without adding meal-start loading.

**Base:** `origin/main` at `1c67c1f6881ccc200b87c7042e42e88182d5fd45`

## 1. Specify cache and migration behavior with failing tests

- Extend `ChewDetectionPersonalizationTests.swift` for account/model isolation, unresolved versus resolved-no-profile state, 24-hour freshness, and legacy UserDefaults migration.
- Add remote profile DTO/client tests for current fetch, save, reset, and nil current responses.
- Run focused tests and confirm the new behavior is absent.

## 2. Implement the account-scoped cache and remote sync

- Add profile identity/revision DTOs and Spring API calls.
- Replace the global-only lookup with a cache keyed by authenticated user ID and DSP model version.
- Sync after login/auth restoration, on stale foreground activation, and after save/reset; a fresh cache must not trigger another request.
- If both server and legacy local data exist, keep the server profile; import legacy data only when the server has no current profile.

## 3. Freeze the meal-start DSP context

- Make `MealSessionRuntimeStore` resolve configuration and optional profile ID synchronously from the cache when the meal begins.
- Keep that snapshot for the complete session even if the cache changes later.
- Extend session upload DTO mapping with nullable `chewDetectionProfileId` and do not call the profile API from the meal-start path.

## 4. Make personalization activation transactional from the user's perspective

- Save personalization to the server before replacing the active cached profile.
- Keep the previous profile on failure and expose retry/error state in the existing personalization flow.
- Reset through the server, then update the cache only after success.

## 5. Verify UX and compatibility

- Generate the Tuist project using the existing local secrets configuration without copying secrets into Git.
- Run focused cache/runtime/upload tests, then the full iOS test suite available in the workspace.
- Confirm no new meal-start loading state exists and old/default sessions still upload with a nil profile ID.
