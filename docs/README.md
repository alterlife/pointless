# Documentation

## Active Design Documents

### [METAPROGRAMMING_ARCHITECTURE.md](./METAPROGRAMMING_ARCHITECTURE.md)

**The definitive architecture for comment elimination through metaprogramming.**

Proposes using:
- **@PeriodicUpdate property wrapper** - Encapsulates timer lifecycle management
- **@PluginSetting property wrapper** - Auto-persists settings, generates UI
- **@Plugin macro** - Generates Plugin protocol conformance at compile time

**Result:** CPUPlugin goes from 118 lines → 45 lines, zero boilerplate, zero comments needed.

**Status:** Ready for review and implementation.

---

## Project Documentation (Root Level)

- **[CLAUDE.md](../CLAUDE.md)** - Project instructions for Claude Code (build commands, architecture, patterns)
- **[DESIGN.md](../DESIGN.md)** - Original architecture documentation
- **[CUSTOM_VIEWS.md](../CUSTOM_VIEWS.md)** - Examples of custom menu bar views
- **[AGENTS.md](../AGENTS.md)** - Agent configuration (if applicable)
