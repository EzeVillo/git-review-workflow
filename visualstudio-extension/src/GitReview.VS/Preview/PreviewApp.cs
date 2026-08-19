using System.Windows;
using GitReview.Domain;
using GitReview.Fixtures;
using GitReview.VS.ToolWindows;

namespace GitReview.VS.Preview;

/// <summary>
/// Standalone WPF preview of every PanelModel fixture (parity with JetBrains runPanelPreview).
/// Run: dotnet run --project src/GitReview.VS -- --preview
/// </summary>
public static class PreviewApp
{
    [STAThread]
    public static int Run()
    {
        var app = new Application();
        var window = new Window
        {
            Title = "git review — panel preview",
            Width = 380,
            Height = 720,
        };

        var fixtures = PanelFixtures.All();
        var index = 0;
        // The panel bakes its chrome in at construction (same as the tool window,
        // which rebuilds on VSColorTheme.ThemeChanged), so switching themes here
        // swaps the view rather than repainting it.
        var dark = true;
        PanelView panel = null!;

        var root = new System.Windows.Controls.DockPanel();
        var nav = new System.Windows.Controls.StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            Margin = new Thickness(4),
        };
        var prev = new System.Windows.Controls.Button { Content = "◀ Prev", Margin = new Thickness(0, 0, 4, 0), Padding = new Thickness(8, 4, 8, 4) };
        var next = new System.Windows.Controls.Button { Content = "Next ▶", Margin = new Thickness(0, 0, 12, 0), Padding = new Thickness(8, 4, 8, 4) };
        var theme = new System.Windows.Controls.Button { Padding = new Thickness(8, 4, 8, 4) };

        void Show(int i)
        {
            index = (i + fixtures.Count) % fixtures.Count;
            var (name, model) = fixtures[index];
            window.Title = $"git review preview — {name} ({(dark ? "dark" : "light")})";
            var layout = PanelLayoutBuilder.PanelLayout(model);
            panel.Render(layout);
        }

        void Rebuild()
        {
            var chrome = dark ? PanelChrome.DefaultDark : PanelChrome.DefaultLight;
            window.Background = chrome.Background;
            theme.Content = dark ? "Theme: dark" : "Theme: light";
            if (panel is not null) root.Children.Remove(panel);
            panel = new PanelView(chrome);
            root.Children.Add(panel);
            Show(index);
        }

        prev.Click += (_, _) => Show(index - 1);
        next.Click += (_, _) => Show(index + 1);
        theme.Click += (_, _) => { dark = !dark; Rebuild(); };
        nav.Children.Add(prev);
        nav.Children.Add(next);
        nav.Children.Add(theme);
        System.Windows.Controls.DockPanel.SetDock(nav, System.Windows.Controls.Dock.Top);
        root.Children.Add(nav);
        window.Content = root;

        window.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Left) Show(index - 1);
            if (e.Key == System.Windows.Input.Key.Right) Show(index + 1);
            if (e.Key == System.Windows.Input.Key.T) { dark = !dark; Rebuild(); }
        };

        Rebuild();
        app.Run(window);
        return 0;
    }
}
