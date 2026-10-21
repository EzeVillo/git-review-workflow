using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using GitReview.Domain;
using GitReview.VS.ToolWindows;

namespace GitReview.VS.Preview;

internal static class CommentsComposerChecks
{
    public static void Verify(Action<string, bool, string> check)
    {
        var previous = GitReviewDialogs.Chrome;
        try
        {
            foreach (var (theme, chrome) in new[] { ("dark", PanelChrome.DefaultDark), ("light", PanelChrome.DefaultLight) })
            foreach (var selection in new[] { false, true })
            foreach (var (width, height) in new[] { (640, 500), (420, 320) })
            {
                GitReviewDialogs.Chrome = chrome;
                var capture = selection ? new CommentCapture("src/checkout/CheckoutService.cs", "head", 2, 8, true,
                    HasSelection: true, Snippet: "public async Task Checkout()\n{\n    await Validate();\n    await Save();\n}") : null;
                var window = new CommentsComposer(capture, new[]{"local", "shared"}, (_, _, _) => Task.FromResult<string?>(null));
                var content = (FrameworkElement)window.Content;
                window.Content = null;
                var surface = new Border { Child = content };
                surface.Measure(new Size(width, height));
                surface.Arrange(new Rect(0, 0, width, height));
                surface.UpdateLayout();
                var controls = Children(surface).OfType<System.Windows.Controls.Control>().ToArray();
                var body = controls.OfType<TextBox>().Single(c => c.AcceptsReturn);
                var bounds = body.TransformToAncestor(surface).TransformBounds(new Rect(body.RenderSize));
                var buttons = controls.OfType<Button>().Where(c => Equals(c.Content, CommentsCopy.submit) || Equals(c.Content, CommentsCopy.cancel)).ToArray();
                var firstButton = buttons.Min(b => b.TransformToAncestor(surface).TransformBounds(new Rect(b.RenderSize)).Top);
                var destination = controls.OfType<ComboBox>().Single(c => c.SelectedIndex < 0);
                var destinationBounds = destination.TransformToAncestor(surface).TransformBounds(new Rect(destination.RenderSize));
                var name = $"composer:{theme}:{selection}:{width}x{height}";
                check(name + ":theme", Equals(window.Background, chrome.Background) && Equals(window.Foreground, chrome.Foreground)
                    && Equals(body.Background, chrome.CodeBackground) && Equals(body.Foreground, chrome.Foreground), "Host palette must reach the window and editor");
                check(name + ":input-theme", controls.OfType<ComboBox>().All(c => Children(c).OfType<Border>().Any(b => Equals(b.Background, chrome.CodeBackground))),
                    "Rendered selectors must use the host palette instead of OS colors");
                check(name + ":writing-area", bounds.Height >= 80 && bounds.Top >= 0 && bounds.Bottom <= firstButton
                    && bounds.Right <= width && bounds.Left >= 0, $"body={bounds}, buttons={firstButton}");
                check(name + ":buttons", buttons.Length == 2 && buttons.All(b => b.ActualHeight >= 28 && b.ActualWidth >= 72), "Save and Cancel must remain usable");
                check(name + ":destination", destinationBounds.Top >= 0 && destinationBounds.Bottom <= bounds.Top,
                    "Destination must stay visible above the editor when context scrolls");
                window.Close();
            }
            foreach (var kind in new[]{"local", "shared"})
            {
                string? submitted = null;
                var window = new CommentsComposer(null, new[]{kind}, (destination, _, _) => {submitted=destination; return Task.FromResult<string?>(null);});
                var content = (FrameworkElement)window.Content;
                content.Measure(new Size(640, 500));content.Arrange(new Rect(0, 0, 640, 500));content.UpdateLayout();
                var controls = Children(content).OfType<System.Windows.Controls.Control>().ToArray();
                var body = controls.OfType<TextBox>().Single(c=>c.AcceptsReturn);
                var destination = controls.OfType<ComboBox>().Single(c=>System.Windows.Automation.AutomationProperties.GetName(c)==CommentsCopy.destination);
                check("composer:sole:"+kind+":hidden",destination.SelectedIndex==0 && destination.Parent is Grid parent && parent.Visibility==Visibility.Collapsed,"A sole CLI destination must not show a selector");
                body.Text="A note without choosing a destination";
                var save=controls.OfType<Button>().Single(c=>Equals(c.Content,CommentsCopy.submit));
                save.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                check("composer:sole:"+kind+":submit",submitted==kind,"Submit must send the sole CLI destination");
                window.Close();
            }
        }
        finally { GitReviewDialogs.Chrome = previous; }
    }

    private static IEnumerable<DependencyObject> Children(DependencyObject parent)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            yield return child;
            foreach (var descendant in Children(child)) yield return descendant;
        }
    }
}
