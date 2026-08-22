using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using GitReview.Domain;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// The dialogs the action matrix needs, in the shapes the other two clients use them:
/// a single-choice picker (VS Code <c>showQuickPick</c>, IntelliJ <c>UiMessages.choose</c>),
/// a one-line input (<c>showInputBox</c> / <c>Messages.showInputDialog</c>), and a
/// confirmation whose affirmative button carries the <see cref="UserCopy"/> label rather
/// than a generic OK.
///
/// Plain WPF on purpose — no <c>Microsoft.VisualStudio.*</c>. Everything under
/// <c>Vsix/</c> is compiled only for net472, so a picker that lived there would be
/// invisible to <see cref="ActionDispatcher"/> and to the standalone <c>--preview</c>
/// build, which is exactly where the wizard is easiest to exercise. The colors come
/// from the panel's own <see cref="PanelChrome"/>, so a dialog opened from a dark IDE
/// is not a white flash.
/// </summary>
public static class GitReviewDialogs
{
    /// <summary>
    /// Set once by <see cref="GitReviewPanelController"/> from the chrome the host
    /// resolved, so these dialogs follow the IDE theme like the panel does.
    /// </summary>
    public static PanelChrome Chrome { get; set; } = PanelChrome.DefaultDark;

    /// <summary>Sentinel for "the reviewer cancelled" in <see cref="Choose"/>.</summary>
    public const int Cancelled = -1;

    public static void Info(string text, string title = UserCopy.ProductTitle) =>
        Show(text, title, MessageBoxImage.Information);

    public static void Warning(string text, string title = UserCopy.ProductTitle) =>
        Show(text, title, MessageBoxImage.Warning);

    public static void Error(string text, string title = UserCopy.ProductTitle) =>
        Show(string.IsNullOrWhiteSpace(text) ? "Operation failed." : text, title, MessageBoxImage.Warning);

    /// <summary>CLI failure: flattened stderr, then stdout, then <paramref name="fallback"/>.</summary>
    public static void CliError(string stderr, string fallback, string stdout = "") =>
        Error(CliMessage.CliErrorText(stderr, stdout, fallback));

    private static void Show(string text, string title, MessageBoxImage icon) =>
        MessageBox.Show(text, title, MessageBoxButton.OK, icon);

    /// <summary>
    /// Modal confirmation. <paramref name="button"/> is the affirmative label from
    /// <see cref="UserCopy"/> ("Start the review", "Cancel Review", …) — the same text
    /// VS Code passes to <c>showWarningMessage</c> and IntelliJ to <c>showYesNoDialog</c>.
    /// </summary>
    public static bool Confirm(string title, string detail, string button)
    {
        var dialog = new ConfirmDialog(title, string.IsNullOrWhiteSpace(detail) ? title : detail, button);
        return dialog.ShowDialog() == true;
    }

    /// <summary>
    /// Single-choice picker. Returns the index into <paramref name="options"/>, or
    /// <see cref="Cancelled"/> when the reviewer closes it — every caller treats a
    /// cancel as "do nothing", never as "take the first one".
    /// </summary>
    public static int Choose(
        string title,
        string message,
        IReadOnlyList<string> options,
        int defaultIndex = 0)
    {
        if (options.Count == 0) return Cancelled;
        var dialog = new ChooseDialog(title, message, options, defaultIndex);
        return dialog.ShowDialog() == true ? dialog.SelectedIndex : Cancelled;
    }

    /// <summary>
    /// Same picker, but the typed text is itself an answer: the filter box offers what
    /// was typed as the first row whenever it does not match an option exactly. Only
    /// <c>compare</c> needs it — it takes a commit-ish, and a tag or a SHA is a
    /// legitimate answer no branch list carries. Every other picker stays closed over
    /// its options, where a typo cannot become a branch name nobody meant.
    /// Null on cancel and on empty.
    /// </summary>
    public static string? ChooseOrType(string title, string message, IReadOnlyList<string> options)
    {
        var dialog = new ChooseDialog(title, message, options, 0, freeText: true);
        if (dialog.ShowDialog() != true) return null;
        var text = dialog.SelectedLabel?.Trim();
        return string.IsNullOrEmpty(text) ? null : text;
    }

    /// <summary>
    /// One-line input. Null on cancel <em>and</em> on empty, so a caller cannot end up
    /// passing "" to the CLI as a branch name.
    /// </summary>
    public static string? Input(string title, string prompt, string? initial = null)
    {
        var dialog = new InputDialog(title, prompt, initial);
        if (dialog.ShowDialog() != true) return null;
        var text = dialog.Value.Trim();
        return text.Length == 0 ? null : text;
    }

    // -- window plumbing ----------------------------------------------------

    [DllImport("user32.dll")]
    private static extern IntPtr GetActiveWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect32 rect);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect32
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    /// <summary>
    /// Base of the three dialogs: chrome, sizing, buttons, and an owner.
    ///
    /// The owner is set through <see cref="WindowInteropHelper"/> because the host is
    /// devenv (a Win32 window), not a WPF <see cref="Window"/> we could assign: without
    /// it the dialog is a top-level window that the IDE can be raised over, and a modal
    /// dialog hidden behind the shell looks exactly like a frozen IDE. WPF's
    /// <c>CenterOwner</c> only understands a WPF owner, so the position is computed from
    /// the owner's rect instead of asking for it.
    ///
    /// It has to be set from the constructor, before <c>ShowDialog</c>: the interop
    /// helper writes through to <c>Window.OwnerHandle</c>, which refuses once the window
    /// is being shown modally ("Cannot set Owner property after Dialog is shown"), and
    /// <c>ShowDialog</c> flips that flag before it creates the HWND — so doing this from
    /// <c>OnSourceInitialized</c> is already too late and throws every time. Capturing
    /// the active window this early is also the more correct owner: it is the IDE for
    /// certain, since this dialog has no HWND yet to be the active one.
    /// </summary>
    private abstract class DialogBase : Window
    {
        private readonly StackPanel _body;
        protected PanelChrome Chrome { get; }

        protected DialogBase(string title, double minWidth = 460)
        {
            Chrome = GitReviewDialogs.Chrome;
            _owner = GetActiveWindow();
            if (_owner != IntPtr.Zero) new WindowInteropHelper(this) { Owner = _owner };
            Title = title;
            Background = Chrome.Background;
            Foreground = Chrome.Foreground;
            FontFamily = Chrome.Ui;
            FontSize = 12;
            ShowInTaskbar = false;
            SizeToContent = SizeToContent.WidthAndHeight;
            ResizeMode = ResizeMode.CanResize;
            MinWidth = minWidth;
            MaxWidth = 760;
            // Centered on the screen until it can be centered on the IDE, which needs a
            // laid-out size to subtract — see OnSourceInitialized / Loaded below.
            WindowStartupLocation = WindowStartupLocation.CenterScreen;

            _body = new StackPanel { Margin = new Thickness(14) };
            Content = _body;
            Loaded += (_, _) => CenterOnOwner();
        }

        protected void Add(UIElement element) => _body.Children.Add(element);

        protected TextBlock Label(string text) => new()
        {
            Text = text,
            TextWrapping = TextWrapping.Wrap,
            Foreground = Chrome.Foreground,
            Margin = new Thickness(0, 0, 0, 8),
        };

        /// <summary>The affirmative/cancel pair, right-aligned as Windows dialogs are.</summary>
        protected void AddButtons(string acceptLabel)
        {
            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(0, 14, 0, 0),
            };
            var accept = new Button
            {
                Content = acceptLabel,
                IsDefault = true,
                MinWidth = 88,
                Padding = new Thickness(10, 4, 10, 4),
            };
            accept.Click += (_, _) => Accept();
            var cancel = new Button
            {
                Content = "Cancel",
                IsCancel = true,
                MinWidth = 88,
                Margin = new Thickness(8, 0, 0, 0),
                Padding = new Thickness(10, 4, 10, 4),
            };
            row.Children.Add(accept);
            row.Children.Add(cancel);
            Add(row);
        }

        /// <summary>Closes with success. Overridden where an empty selection cannot accept.</summary>
        protected virtual void Accept()
        {
            DialogResult = true;
            Close();
        }

        /// <summary>
        /// Captured in the constructor: <see cref="GetActiveWindow"/> answers this
        /// thread's active window, which is the IDE right up until this dialog becomes it.
        /// </summary>
        private readonly IntPtr _owner;

        /// <summary>
        /// Runs from Loaded, where the dialog has a laid-out size to subtract, and still
        /// before the first render — so this is a position, not a jump.
        /// </summary>
        private void CenterOnOwner()
        {
            if (_owner == IntPtr.Zero || !GetWindowRect(_owner, out var rect)) return;
            var source = PresentationSource.FromVisual(this);
            var transform = source?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;
            var topLeft = transform.Transform(new Point(rect.Left, rect.Top));
            var bottomRight = transform.Transform(new Point(rect.Right, rect.Bottom));
            var width = ActualWidth > 0 ? ActualWidth : DesiredSize.Width;
            var height = ActualHeight > 0 ? ActualHeight : DesiredSize.Height;
            Left = topLeft.X + ((bottomRight.X - topLeft.X) - width) / 2;
            Top = topLeft.Y + ((bottomRight.Y - topLeft.Y) - height) / 3;
        }
    }

    private sealed class ConfirmDialog : DialogBase
    {
        public ConfirmDialog(string title, string detail, string button) : base(title)
        {
            Add(Label(detail));
            AddButtons(button);
        }
    }

    private sealed class InputDialog : DialogBase
    {
        private readonly TextBox _input;

        public string Value => _input.Text;

        public InputDialog(string title, string prompt, string? initial) : base(title)
        {
            Add(Label(prompt));
            _input = new TextBox
            {
                Text = initial ?? "",
                Background = Chrome.CodeBackground,
                Foreground = Chrome.Foreground,
                BorderBrush = Chrome.Border,
                BorderThickness = new Thickness(1),
                Padding = new Thickness(5, 4, 5, 4),
                FontFamily = Chrome.Mono,
                MinWidth = 420,
                CaretBrush = Chrome.Foreground,
            };
            _input.SelectAll();
            Add(_input);
            AddButtons("OK");
            Loaded += (_, _) =>
            {
                _input.Focus();
                _input.SelectAll();
            };
        }
    }

    /// <summary>
    /// The picker. A list rather than a combo — this is the surface a reviewer reads a
    /// branch list off, and VS Code's quick pick shows the options at once. The filter
    /// box appears only once a list is long enough to need one; it filters what is
    /// shown without renumbering anything, because the result is an index into the
    /// caller's own array.
    /// </summary>
    private sealed class ChooseDialog : DialogBase
    {
        private readonly IReadOnlyList<string> _options;
        private readonly ListBox _list = new();
        private readonly TextBox _filter = new();
        private readonly bool _freeText;

        public int SelectedIndex =>
            _list.SelectedItem is Row row && row.Index != PickerRows.Typed ? row.Index : Cancelled;

        /// <summary>The picked text — an option, or what was typed in free-text mode.</summary>
        public string? SelectedLabel => (_list.SelectedItem as Row)?.Value;

        public ChooseDialog(
            string title,
            string message,
            IReadOnlyList<string> options,
            int defaultIndex,
            bool freeText = false) : base(title)
        {
            _options = options;
            _freeText = freeText;
            if (!string.IsNullOrWhiteSpace(message)) Add(Label(message));

            _filter.Background = Chrome.CodeBackground;
            _filter.Foreground = Chrome.Foreground;
            _filter.BorderBrush = Chrome.Border;
            _filter.BorderThickness = new Thickness(1);
            _filter.Padding = new Thickness(5, 3, 5, 3);
            _filter.Margin = new Thickness(0, 0, 0, 6);
            _filter.CaretBrush = Chrome.Foreground;
            // Siempre visible, sin umbral por cantidad: el filtro es la forma de
            // elegir, no una ayuda para listas largas. Un picker que la esconde
            // con pocas opciones enseña dos interacciones distintas para la
            // misma pregunta, y la que se aprende primero es la que no filtra.
            _filter.Visibility = Visibility.Visible;
            _filter.TextChanged += (_, _) => ApplyFilter();
            // Down from the filter walks into the list instead of dead-ending.
            _filter.PreviewKeyDown += (_, e) =>
            {
                if (e.Key != Key.Down) return;
                _list.Focus();
                e.Handled = true;
            };
            Add(_filter);

            _list.Background = Chrome.CodeBackground;
            _list.Foreground = Chrome.Foreground;
            _list.BorderBrush = Chrome.Border;
            _list.BorderThickness = new Thickness(1);
            _list.MaxHeight = 380;
            _list.MinWidth = 420;
            _list.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            ScrollViewer.SetHorizontalScrollBarVisibility(_list, ScrollBarVisibility.Auto);
            // The selection highlight is a system color by default, which follows
            // Windows rather than the IDE: a dark panel would draw the picked row in
            // light blue with light text on it.
            _list.Resources[SystemColors.HighlightBrushKey] = Chrome.RowSelected;
            _list.Resources[SystemColors.HighlightTextBrushKey] = Chrome.Foreground;
            _list.Resources[SystemColors.InactiveSelectionHighlightBrushKey] = Chrome.RowSelected;
            _list.Resources[SystemColors.InactiveSelectionHighlightTextBrushKey] = Chrome.Foreground;
            _list.MouseDoubleClick += (_, _) =>
            {
                if (SelectedIndex != Cancelled) Accept();
            };
            Add(_list);

            AddButtons("OK");
            ApplyFilter();
            var wanted = defaultIndex >= 0 && defaultIndex < options.Count ? defaultIndex : 0;
            Select(wanted);
            Loaded += (_, _) =>
            {
                _filter.Focus();
                _list.ScrollIntoView(_list.SelectedItem);
            };
        }

        /// <summary>Enter on the list is the same as pressing the default button.</summary>
        protected override void Accept()
        {
            if (_freeText)
            {
                if (string.IsNullOrWhiteSpace(SelectedLabel)) return;
            }
            else if (SelectedIndex == Cancelled)
            {
                return;
            }

            base.Accept();
        }

        private void Select(int original)
        {
            foreach (var item in _list.Items)
                if (item is Row row && row.Index == original)
                {
                    _list.SelectedItem = item;
                    return;
                }
            if (_list.Items.Count > 0) _list.SelectedIndex = 0;
        }

        private void ApplyFilter()
        {
            var needle = _filter.Text.Trim();
            var keep = SelectedIndex;
            var rows = PickerRows.Rows(_options, needle, _freeText);

            _list.Items.Clear();
            foreach (var index in rows)
            {
                _list.Items.Add(index == PickerRows.Typed
                    ? new Row(index, needle, "   — use as typed")
                    : new Row(index, _options[index]));
            }

            _list.SelectedIndex = PickerRows.Selection(rows, keep);
        }

        /// <summary>
        /// One row. Carries the index into the caller's array so filtering never
        /// changes what a selection means, and a tooltip for the label that does not
        /// fit the dialog's maximum width.
        /// </summary>
        private sealed class Row : TextBlock
        {
            public int Index { get; }

            /// <summary>
            /// Lo que el diálogo devuelve, aparte de lo que dibuja: la fila de texto
            /// libre lleva un sufijo que la explica y que no es parte de la respuesta.
            /// </summary>
            public string Value { get; }

            public Row(int index, string label, string? suffix = null)
            {
                Index = index;
                Value = label;
                Text = suffix is null ? label : label + suffix;
                ToolTip = Text;
                Padding = new Thickness(4, 2, 4, 2);
                TextTrimming = TextTrimming.None;
            }
        }
    }
}
