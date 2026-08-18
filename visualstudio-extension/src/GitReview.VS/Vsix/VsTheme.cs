using System.Windows.Media;
using Microsoft.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Shell;
using GitReview.VS.ToolWindows;
using DrawingColor = System.Drawing.Color;

namespace GitReview.VS.Vsix;

/// <summary>
/// Builds the panel's <see cref="PanelChrome"/> from Visual Studio's environment
/// colors, so the tool window reads as part of the IDE in every theme. Structure and
/// labels stay identical to the other clients; only colors follow the host.
/// </summary>
public static class VsTheme
{
    public static PanelChrome Chrome()
    {
        var background = Themed(EnvironmentColors.ToolWindowBackgroundColorKey);
        var foreground = Themed(EnvironmentColors.ToolWindowTextColorKey);
        if (background is null || foreground is null)
            return PanelChrome.DefaultDark;

        // The theme is whatever the tool window background says it is: VS ships light,
        // dark and blue variants, plus whatever a theme extension installs.
        var basis = IsDark(background.Value) ? PanelChrome.DefaultDark : PanelChrome.DefaultLight;

        return new PanelChrome
        {
            Background = new SolidColorBrush(background.Value),
            Foreground = new SolidColorBrush(foreground.Value),
            MutedForeground = Brush(EnvironmentColors.PanelHyperlinkDisabledColorKey) ?? basis.MutedForeground,
            Border = Brush(EnvironmentColors.ToolWindowBorderColorKey) ?? basis.Border,
            CodeBackground = Brush(EnvironmentColors.ComboBoxBackgroundColorKey) ?? basis.CodeBackground,
            WarningBackground = basis.WarningBackground,
            WarningBorder = basis.WarningBorder,
            LinkForeground = Brush(EnvironmentColors.PanelHyperlinkColorKey) ?? basis.LinkForeground,
            PrimaryBackground = basis.PrimaryBackground,
            PrimaryForeground = basis.PrimaryForeground,
            SecondaryBackground = Brush(EnvironmentColors.CommandBarGradientBeginColorKey) ?? basis.SecondaryBackground,
            RowHover = Brush(EnvironmentColors.CommandBarMenuItemMouseOverColorKey) ?? basis.RowHover,
            RowSelected = Brush(EnvironmentColors.SystemHighlightColorKey) ?? basis.RowSelected,
            // The badge pair stays out of the host's hands: it is the one fill that
            // has to keep its own text legible, and no environment key owns both
            // halves of it. The skeleton has no key behind it either, but it holds
            // no text, so it is mixed out of the panel's own two colors — a theme
            // extension can put any background here, and a fill picked for the
            // stock dark theme reads as a foreign rectangle over it.
            BadgeBackground = basis.BadgeBackground,
            BadgeForeground = basis.BadgeForeground,
            Skeleton = Blend(foreground.Value, background.Value, 0.22),
            Mono = basis.Mono,
            Ui = basis.Ui,
        };
    }

    private static SolidColorBrush? Brush(ThemeResourceKey key)
    {
        var color = Themed(key);
        return color is null ? null : new SolidColorBrush(color.Value);
    }

    private static Color? Themed(ThemeResourceKey key)
    {
        try
        {
            return Convert(VSColorTheme.GetThemedColor(key));
        }
        catch
        {
            // A theme that does not define the key: fall back to the static chrome.
            return null;
        }
    }

    private static Color Convert(DrawingColor c) => Color.FromArgb(c.A, c.R, c.G, c.B);

    /// <summary>Lays <paramref name="over"/> on <paramref name="under"/> at the given weight.</summary>
    private static SolidColorBrush Blend(Color over, Color under, double weight) =>
        new(Color.FromRgb(
            (byte)(over.R * weight + under.R * (1 - weight)),
            (byte)(over.G * weight + under.G * (1 - weight)),
            (byte)(over.B * weight + under.B * (1 - weight))));

    private static bool IsDark(Color c) =>
        (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) < 128.0;
}
