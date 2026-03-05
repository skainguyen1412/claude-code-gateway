# Adding Custom Provider Support Design

## Overview
This feature allows users to configure a custom endpoint for any language model host that speaks either the OpenAI or Gemini API protocols. This gives the app the flexibility to support local providers (Ollama, LM Studio) and newly emerging cloud providers.

## Goals
1. Provide a button in the UI (`ProvidersView`) to start creating a new Custom Provider.
2. Initialize this Custom Provider with sensible defaults.
3. Allow the user to specify whether the remote endpoint uses the `openai` or `gemini` adapter protocol.
4. Cleanly handle the "drafting" state so no empty or invalid configurations are written to permanent storage and clutter the list if the user cancels.

## User Interface Flow
1. **Sidebar Navigation**: The user clicks a `+ Add Custom Provider` button situated at the bottom of the sidebar list in `ProvidersView`.
2. **Setup Experience**: When this draft object is selected, `ProviderEditView` displays a form.
    - **Header**: "New Custom Provider"
    - **Name**: Defaults to "New Custom Provider".
    - **Target Type**: A picker for either `openai` or `gemini` protocol.
    - **Base URL**: Empty by default.
    - **API Key**: Empty by default.
3. **Draft Lifecycle**: The UI leverages a temporary state. Only when the user hits **Save** (or "Add Provider") does the config get written into the `GatewayConfig.providers` dictionary using the supplied user's Name. If the user selects a different provider before saving, the draft is abandoned without consequence.

## Technical Strategy
* **`ProviderListItem` Update**: We expand the unified menu enum inside `ProvidersView.swift` to include `.draft`.
    * `enum ProviderListItem: Identifiable { case configured, template, draft }` 
    * The `draft` case presents the "New Custom Provider" row natively within the sidebar `List` while it is active.
* **Selection State**: A new temporary state holding the draft provider logic (`var draftProvider: ProviderConfig?`) can be injected when the "+" button is pressed.
* **Saving Logic**: When hitting "Save" in `ProviderEditView`, we map the temporary Draft into `config.providers`. If the name matches an original template or active provider, it overwrites it. 
* **Model Picker Fallback**: Because custom providers do not have an official Model Catalog, their model selection pickers naturally fallback to plain TextFields where the user can manually type "llama-3-8b" or "deepseek-coder", which the app natively supports.

## Error Handling & Edge Cases
* **Missing Details**: A user cannot save the draft without supplying a `Name` and a `Base URL`.
* **Testing**: The connection test behavior handles arbitrary test endpoints natively using the adapter specified. If it succeeds, the icon changes to a checkmark.
* **Persistence**: The config ensures that after saving, `GatewayConfig.save()` persists the newly created configuration correctly so it persists between app launches.
