using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;

namespace GitReview.VS.ToolWindows;

/// <summary>Which set of colors a panel button takes from <see cref="PanelChrome"/>.</summary>
internal enum PanelButtonKind
{
    /// <summary>The one call to action of a situation (Start a review, Next).</summary>
    Primary,

    /// <summary>Everything else with a fill behind it.</summary>
    Secondary,

    /// <summary>No fill of its own: file rows and section toggles, which paint themselves.</summary>
    Bare,
}

/// <summary>
/// The panel's own button template. WPF's stock one paints hover, pressed and
/// disabled from triggers <i>inside</i> the template, targeting the border element
/// rather than the control, so they beat whatever the panel assigns to the button:
/// a disabled button came out as the Windows fill (#F4F4F4) with #838383 text —
/// a white block with an unreadable label over a dark IDE theme — and a hovered
/// file row flashed the stock light blue instead of <see cref="PanelChrome.RowHover"/>.
/// So the template is ours: a Border painted from the button's own Background,
/// plus style triggers in the host's colors.
/// </summary>
/// <remarks>
/// Style triggers lose against a local value, so a button using
/// <see cref="PanelButtonKind.Primary"/> or <see cref="PanelButtonKind.Secondary"/>
/// must NOT assign Background/Foreground on the instance — the Style setters carry
/// them, which is what leaves the triggers free to override. <see cref="PanelButtonKind.Bare"/>
/// is the opposite case on purpose: it has no color setters, so the caller's local
/// assignment (and its own MouseEnter/MouseLeave) stays in charge.
/// </remarks>
internal static class PanelButtons
{
    public static Style Style(PanelChrome chrome, PanelButtonKind kind)
    {
        var style = new Style(typeof(Button));
        style.Setters.Add(new Setter(Control.TemplateProperty, Template()));
        style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0)));

        if (kind != PanelButtonKind.Bare)
        {
            var back = kind == PanelButtonKind.Primary
                ? chrome.PrimaryBackground
                : chrome.SecondaryBackground;
            var fore = kind == PanelButtonKind.Primary
                ? chrome.PrimaryForeground
                : chrome.Foreground;
            style.Setters.Add(new Setter(Control.BackgroundProperty, back));
            style.Setters.Add(new Setter(Control.ForegroundProperty, fore));
            style.Setters.Add(new Setter(FrameworkElement.CursorProperty, Cursors.Hand));

            var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
            hover.Setters.Add(new Setter(
                Control.BackgroundProperty,
                kind == PanelButtonKind.Primary ? chrome.PrimaryHover : chrome.ButtonHover));
            style.Triggers.Add(hover);

            var pressed = new Trigger { Property = ButtonBase.IsPressedProperty, Value = true };
            pressed.Setters.Add(new Setter(UIElement.OpacityProperty, 0.85));
            style.Triggers.Add(pressed);

            // Last, so it wins over hover: a disabled control can still be hovered.
            var disabled = new Trigger { Property = UIElement.IsEnabledProperty, Value = false };
            disabled.Setters.Add(new Setter(Control.BackgroundProperty, chrome.DisabledBackground));
            disabled.Setters.Add(new Setter(Control.ForegroundProperty, chrome.DisabledForeground));
            disabled.Setters.Add(new Setter(FrameworkElement.CursorProperty, Cursors.Arrow));
            style.Triggers.Add(disabled);
        }

        return style;
    }

    /// <summary>
    /// Border + ContentPresenter, everything template-bound. The label inherits
    /// Foreground from the button, which is how the disabled trigger reaches it
    /// without a TargetName — the stock template has to set TextElement.Foreground
    /// on its presenter for the same reason.
    /// </summary>
    private static ControlTemplate Template()
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
        border.SetValue(Border.BorderBrushProperty, new TemplateBindingExtension(Control.BorderBrushProperty));
        border.SetValue(Border.BorderThicknessProperty, new TemplateBindingExtension(Control.BorderThicknessProperty));
        border.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Control.PaddingProperty));
        border.SetValue(UIElement.SnapsToDevicePixelsProperty, true);

        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(
            FrameworkElement.HorizontalAlignmentProperty,
            new TemplateBindingExtension(Control.HorizontalContentAlignmentProperty));
        content.SetValue(
            FrameworkElement.VerticalAlignmentProperty,
            new TemplateBindingExtension(Control.VerticalContentAlignmentProperty));
        content.SetValue(UIElement.IsHitTestVisibleProperty, false);
        border.AppendChild(content);

        return new ControlTemplate(typeof(Button)) { VisualTree = border };
    }
}
