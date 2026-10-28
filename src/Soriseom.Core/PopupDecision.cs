namespace Soriseom.Core;

public sealed record PopupDecision(PopupAction Action, MediaSnapshot? Track, DateTimeOffset? ReevaluateAt);
