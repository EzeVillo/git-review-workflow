using System.Windows.Media;
using MediaBrush = System.Windows.Media.Brush;
using MediaFontFamily = System.Windows.Media.FontFamily;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// Theme brushes for the panel. Structure/labels match JetBrains/VS Code;
/// colors follow the host theme (VS environment colors when available).
/// </summary>
/// <remarks>
/// The property defaults ARE the dark variant, so <see cref="DefaultDark"/> is a
/// bare <c>new()</c> and <see cref="DefaultLight"/> overrides every one of them.
/// None of them may be a <c>SystemColors</c> brush: those follow the
/// Windows theme, not the IDE's, so a dark VS on a light Windows used to paint
/// this panel white — and the two brushes with no environment key behind them
/// (<see cref="BadgeBackground"/>, <see cref="Skeleton"/>) landed light-on-dark
/// even when the rest of the panel was correctly themed.
/// </remarks>
public sealed class PanelChrome
{
    public MediaBrush Background { get; init; } = new SolidColorBrush(Color.FromRgb(0x1E, 0x1E, 0x1E));
    public MediaBrush Foreground { get; init; } = new SolidColorBrush(Color.FromRgb(0xCC, 0xCC, 0xCC));
    public MediaBrush MutedForeground { get; init; } = new SolidColorBrush(Color.FromRgb(0x9D, 0x9D, 0x9D));
    public MediaBrush Border { get; init; } = new SolidColorBrush(Color.FromRgb(0x3C, 0x3C, 0x3C));
    public MediaBrush CodeBackground { get; init; } = new SolidColorBrush(Color.FromRgb(0x2D, 0x2D, 0x2D));
    public MediaBrush WarningBackground { get; init; } = new SolidColorBrush(Color.FromRgb(0x3D, 0x30, 0x10));
    public MediaBrush WarningBorder { get; init; } = new SolidColorBrush(Color.FromRgb(0xC9, 0x8A, 0x22));
    public MediaBrush LinkForeground { get; init; } = new SolidColorBrush(Color.FromRgb(0x37, 0x9A, 0xF0));
    public MediaBrush PrimaryBackground { get; init; } = new SolidColorBrush(Color.FromRgb(0x0E, 0x63, 0x9C));
    public MediaBrush PrimaryForeground { get; init; } = Brushes.White;
    public MediaBrush SecondaryBackground { get; init; } = new SolidColorBrush(Color.FromRgb(0x3A, 0x3D, 0x41));
    public MediaBrush RowHover { get; init; } = new SolidColorBrush(Color.FromRgb(0x2A, 0x2D, 0x2E));
    public MediaBrush RowSelected { get; init; } = new SolidColorBrush(Color.FromRgb(0x09, 0x41, 0x71));
    public MediaBrush BadgeBackground { get; init; } = new SolidColorBrush(Color.FromRgb(0x4D, 0x4D, 0x4D));
    public MediaBrush BadgeForeground { get; init; } = Brushes.White;
    public MediaBrush Skeleton { get; init; } = new SolidColorBrush(Color.FromRgb(0x3C, 0x3C, 0x3C));

    public MediaFontFamily Mono { get; init; } = new("Cascadia Mono, Consolas, Courier New");
    public MediaFontFamily Ui { get; init; } = new("Segoe UI");

    public static PanelChrome DefaultDark { get; } = new();

    public static PanelChrome DefaultLight { get; } = new()
    {
        Background = Brushes.White,
        Foreground = Brushes.Black,
        MutedForeground = new SolidColorBrush(Color.FromRgb(0x6E, 0x6E, 0x6E)),
        Border = new SolidColorBrush(Color.FromRgb(0xCC, 0xCC, 0xCC)),
        CodeBackground = new SolidColorBrush(Color.FromRgb(0xF3, 0xF3, 0xF3)),
        WarningBackground = new SolidColorBrush(Color.FromRgb(0xFF, 0xF4, 0xCE)),
        WarningBorder = new SolidColorBrush(Color.FromRgb(0xC9, 0x8A, 0x22)),
        LinkForeground = new SolidColorBrush(Color.FromRgb(0x00, 0x66, 0xB8)),
        PrimaryBackground = new SolidColorBrush(Color.FromRgb(0x00, 0x78, 0xD4)),
        PrimaryForeground = Brushes.White,
        SecondaryBackground = new SolidColorBrush(Color.FromRgb(0xE5, 0xE5, 0xE5)),
        RowHover = new SolidColorBrush(Color.FromRgb(0xE8, 0xE8, 0xE8)),
        RowSelected = new SolidColorBrush(Color.FromRgb(0xCC, 0xE8, 0xFF)),
        BadgeBackground = new SolidColorBrush(Color.FromRgb(0xC4, 0xC4, 0xC4)),
        BadgeForeground = new SolidColorBrush(Color.FromRgb(0x33, 0x33, 0x33)),
        Skeleton = new SolidColorBrush(Color.FromRgb(0xDD, 0xDD, 0xDD)),
    };
}
