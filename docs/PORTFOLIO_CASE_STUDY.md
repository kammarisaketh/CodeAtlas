# CodeAtlas Portfolio Case Study

## Overview

CodeAtlas is an AI-powered code intelligence app for engineers who need to understand unfamiliar repositories quickly.

The product connects to GitHub, indexes repository files, and helps users ask focused questions such as:

- Where is authentication implemented?
- What files are involved in this feature?
- What could break if I change this code?
- Review this repository like a senior engineer.

## Problem

Engineers often spend a large amount of time reading unfamiliar code before they can safely make changes. Traditional search helps find text matches, but it does not explain architecture, dependencies, risk, or intent.

CodeAtlas is designed to turn a repository into a navigable knowledge base with citations back to source files.

## Product Goals

- Make repository onboarding faster.
- Help users understand architecture and code ownership.
- Provide review feedback grounded in actual source files.
- Keep repository data private and avoid exposing secrets.
- Build a native iOS experience that feels like a professional Apple app.

## Technical Scope

### iOS

- Swift
- SwiftUI
- MVVM-style organization
- Swift concurrency
- Sign in with Apple
- Keychain token storage
- Native navigation, tabs, cards, empty states, and dark mode support

### Backend

- Python
- FastAPI
- JWT authentication
- GitHub OAuth
- Repository ingestion
- Code indexing
- Local persistence for development
- PostgreSQL-ready architecture
- Docker Compose support
- Pytest test coverage

## Architecture Summary

The iOS app is the user-facing client. It handles authentication, repository management, source browsing, AI-style review screens, and account settings.

The backend is responsible for GitHub OAuth, repository access, indexing, file storage, search, and review generation.

The system is intentionally split so the app can start with mock/demo data while the backend evolves into a production retrieval and LLM pipeline.

## Key Engineering Decisions

- **Protocol-oriented client services**: keeps SwiftUI views separate from networking and persistence details.
- **Backend-first repository processing**: repository tokens and source ingestion stay off the iOS client.
- **Citation-focused design**: the product is built around evidence from files, not generic AI answers.
- **Local-first development mode**: the app can be demonstrated without cloud infrastructure.
- **Security by default**: secrets are ignored in Git, tokens use Keychain, and repository content is treated as sensitive.

## Current Status

Portfolio MVP is complete:

- Native iOS app builds and runs.
- Apple login flow is wired.
- GitHub OAuth flow is wired.
- Backend runs locally.
- Repository add/index flow is available.
- Code review, ask, explore, and account flows are implemented.
- Documentation is ready for GitHub and LinkedIn presentation.

## What I Would Build Next

- Hosted backend deployment.
- Real embedding model and LLM provider integration.
- Background worker queue for large repository indexing.
- Production PostgreSQL deployment with pgvector.
- UI test suite for the main iOS flows.
- Public demo video and App Store-style screenshots.

## Portfolio Positioning

CodeAtlas is best presented as a full-stack iOS engineering project that demonstrates product thinking, native app design, backend architecture, authentication, GitHub integration, repository processing, and AI-ready system design.

