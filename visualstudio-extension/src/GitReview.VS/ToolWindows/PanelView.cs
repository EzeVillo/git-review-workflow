using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using GitReview.Domain;
using DomainControl = GitReview.Domain.Control;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// WPF renderer of <see cref="PanelLayout"/>. Labels, order, and control
/// emphasis match JetBrains PanelRenderer / VS Code panelHtml — only colors
/// follow <see cref="PanelChrome"/>.
/// </summary>
public sealed class PanelView : System.Windows.Controls.UserControl
{
    private readonly PanelChrome _chrome;
    private readonly Style _primaryButton;
    private readonly Style _secondaryButton;
    private readonly Style _bareButton;
    private readonly Dictionary<string, bool> _sectionOpen = new();
    private readonly ScrollViewer _scroll;
    private readonly StackPanel _body;
    private readonly StackPanel _footer;
    private readonly DockPanel _root;
    private readonly StackPanel _titleBar;

    /// <summary>ControlId wire, optional inventory/file index, optional support link id.</summary>
    public event Action<string, int?, string?>? ActionRequested;

    /// <summary>
    /// Whether the five title actions are drawn as a row inside the pane. False in
    /// the Visual Studio tool window, where the shell draws them as the window's own
    /// toolbar (the same place VS Code and IntelliJ put them) and drawing them here
    /// as well would show every one of them twice. The standalone preview has no
    /// window frame to hang a toolbar on, so it keeps them.
    /// </summary>
    public bool ShowTitleActions { get; set; } = true;

    public PanelView(PanelChrome? chrome = null)
    {
        _chrome = chrome ?? PanelChrome.DefaultDark;
        _primaryButton = PanelButtons.Style(_chrome, PanelButtonKind.Primary);
        _secondaryButton = PanelButtons.Style(_chrome, PanelButtonKind.Secondary);
        _bareButton = PanelButtons.Style(_chrome, PanelButtonKind.Bare);
        Background = _chrome.Background;

        _titleBar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(4, 4, 4, 0),
        };

        _body = new StackPanel { Margin = new Thickness(8) };
        _footer = new StackPanel { Margin = new Thickness(8, 0, 8, 8) };

        _scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _body,
        };

        _root = new DockPanel { Background = _chrome.Background };
        DockPanel.SetDock(_titleBar, Dock.Top);
        DockPanel.SetDock(_footer, Dock.Bottom);
        _root.Children.Add(_titleBar);
        _root.Children.Add(_footer);
        _root.Children.Add(_scroll);
        Content = _root;
    }

    /// <summary>
    /// Before the first refresh has resolved anything. The state manager's seed is a
    /// placeholder, so rendering it would announce a missing CLI -- with an Install
    /// button -- for the couple of seconds the first status takes, every time the
    /// window opens. The other two clients hold the same way: IntelliJ paints this
    /// line and the VS Code webview stays empty until the first model arrives.
    /// </summary>
    public void RenderWaiting()
    {
        _titleBar.Children.Clear();
        _titleBar.Visibility = Visibility.Collapsed;
        _body.Children.Clear();
        _footer.Children.Clear();
        _body.Children.Add(new TextBlock
        {
            Text = WaitingText,
            FontFamily = _chrome.Ui,
            FontSize = 12,
            Foreground = _chrome.MutedForeground,
            TextWrapping = TextWrapping.Wrap,
        });
    }

    /// <summary>Same words as the JetBrains panel's pre-first-refresh surface.</summary>
    private const string WaitingText = "Reading the review state…";

    /// <summary>
    /// Last-resort fallback when <see cref="Render"/> itself throws. The normal render
    /// path clears the panel before drawing the new content, so an exception partway
    /// through — a block variant this WPF renderer does not handle, for example —
    /// otherwise leaves the tool window permanently blank with no visible trace: the
    /// domain-side --verify fixtures only exercise PanelLayoutBuilder, never this
    /// renderer, so a gap here would not show up there.
    /// </summary>
    public void RenderFatal(Exception ex)
    {
        _titleBar.Children.Clear();
        _titleBar.Visibility = Visibility.Collapsed;
        _body.Children.Clear();
        _footer.Children.Clear();
        _body.Children.Add(new TextBlock
        {
            Text = "git review panel failed to render:\n" + ex,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = _chrome.Mono,
            FontSize = 11,
            Foreground = _chrome.Foreground,
        });
    }

    public void Render(PanelLayout layout)
    {
        _titleBar.Children.Clear();
        _body.Children.Clear();
        _footer.Children.Clear();

        if (ShowTitleActions)
        {
            foreach (var c in layout.TitleActions)
                _titleBar.Children.Add(RenderTitleControl(c));
        }

        // Collapsed rather than empty: an empty StackPanel still spends its margin,
        // which would leave a strip of padding above the panel in the tool window.
        _titleBar.Visibility = _titleBar.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        var bodyBlocks = new List<Block>();
        var footerBlocks = new List<Block>();
        foreach (var b in layout.Blocks)
        {
            if (b is Block.ToolsSection) footerBlocks.Add(b);
            else bodyBlocks.Add(b);
        }

        foreach (var b in bodyBlocks)
        {
            _body.Children.Add(RenderBlock(b));
            _body.Children.Add(new Border { Height = 4, Background = Brushes.Transparent });
        }

        if (layout.FillsHeight)
        {
            // Spacer so tools sit at the bottom of the tool window
            _body.Children.Add(new Border { Height = 1, Background = Brushes.Transparent });
            foreach (var b in footerBlocks)
                _footer.Children.Add(RenderBlock(b));
        }
        else
        {
            foreach (var b in footerBlocks)
                _body.Children.Add(RenderBlock(b));
        }
    }

    private UIElement RenderBlock(Block block) => block switch
    {
        Block.IdentityBar bar => RenderIdentityBar(bar),
        Block.Note n => RenderNote(n),
        Block.Paragraph p => RenderParagraph(p),
        Block.Heading h => new TextBlock
        {
            Text = h.Text,
            FontFamily = _chrome.Ui,
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            Foreground = _chrome.MutedForeground,
            TextWrapping = TextWrapping.Wrap,
        },
        Block.Banner b => RenderBanner(b),
        Block.CodeCommand c => RenderCodeCommand(c),
        Block.EntryHead e => RenderEntryHead(e),
        Block.EntryTitle t => t.IsSkeleton
            ? SkeletonBar(0.6)
            : new TextBlock
            {
                Text = t.Text,
                FontFamily = t.Muted ? _chrome.Ui : _chrome.Mono,
                FontSize = 12,
                FontStyle = t.Muted ? FontStyles.Italic : FontStyles.Normal,
                Foreground = t.Muted ? _chrome.MutedForeground : _chrome.Foreground,
                TextWrapping = TextWrapping.Wrap,
            },
        Block.Why w => RenderWhy(w),
        Block.Row r => RenderRow(r.Controls),
        Block.FileRows f => RenderFileRows(f),
        Block.InventoryRows inv => RenderInventory(inv),
        Block.DraftRows drafts => RenderDrafts(drafts),
        Block.GuideRows guides => RenderGuides(guides),
        Block.ToolsSection ts => RenderToolsSection(ts),
        Block.Stderr s => RenderStderr(s.Text),
        Block.EmptyMessage em => RenderEmpty(em),
        Block.Skeleton sk => SkeletonBar(sk.Shape switch
        {
            SkeletonShape.Pos => 0.25,
            SkeletonShape.Num => 0.15,
            SkeletonShape.Title => 0.5,
            SkeletonShape.WhyLine => 0.7,
            _ => 0.8,
        }),
        _ => new TextBlock { Text = "?" },
    };

    private UIElement RenderIdentityBar(Block.IdentityBar bar)
    {
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(MonoLabel(bar.Mode, bold: true));
        if (bar.Draft) left.Children.Add(MonoLabel("(draft)", marginLeft: 6));
        left.Children.Add(MonoLabel(bar.Name, marginLeft: 6));
        if (bar.Tip is not null) left.Children.Add(MonoLabel(bar.Tip, marginLeft: 6));

        var right = new StackPanel { Orientation = Orientation.Horizontal };
        if (bar.IsSkeleton) right.Children.Add(SkeletonBar(0.2, 18));
        else if (bar.Position is not null && bar.Total is not null)
            right.Children.Add(MonoLabel($"{bar.Position}/{bar.Total}"));

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(left, 0);
        Grid.SetColumn(right, 1);
        grid.Children.Add(left);
        grid.Children.Add(right);

        return new Border
        {
            BorderBrush = _chrome.Border,
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(0, 0, 0, 6),
            Child = grid,
        };
    }

    private UIElement RenderNote(Block.Note note) =>
        new Border
        {
            BorderBrush = _chrome.Border,
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(0, 0, 0, 6),
            Child = WrapText(note.Text, muted: true),
        };

    private UIElement RenderParagraph(Block.Paragraph p)
    {
        var text = WrapText(p.Text, muted: p.Muted);
        if (!p.Separated) return text;
        return new Border
        {
            BorderBrush = _chrome.Border,
            BorderThickness = new Thickness(0, 1, 0, 0),
            Padding = new Thickness(0, 8, 0, 0),
            Child = text,
        };
    }

    private UIElement RenderEntryHead(Block.EntryHead head)
    {
        if (head.IsSkeleton) return SkeletonBar(0.3);
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        var n = head.Position < 10 ? $"0{head.Position}" : head.Position.ToString();
        left.Children.Add(MonoLabel(n, bold: true));
        if (head.Identifier is not null) left.Children.Add(MonoLabel(head.Identifier, marginLeft: 6));
        if (head.Author is not null) left.Children.Add(MonoLabel(head.Author, marginLeft: 6));
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        if (head.Badge is not null) right.Children.Add(Chip(head.Badge));
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(left, 0);
        Grid.SetColumn(right, 1);
        grid.Children.Add(left);
        grid.Children.Add(right);
        return grid;
    }

    private UIElement RenderWhy(Block.Why why)
    {
        UIElement content = why.State switch
        {
            WhyState.Loading => new StackPanel
            {
                Children =
                {
                    SkeletonBar(1.0),
                    new Border { Height = 2 },
                    SkeletonBar(0.8),
                    new Border { Height = 2 },
                    SkeletonBar(0.6),
                },
            },
            WhyState.Present => WrapText(why.Text ?? ""),
            _ => new TextBlock
            {
                Text = why.Text ?? "",
                FontStyle = FontStyles.Italic,
                Foreground = _chrome.MutedForeground,
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12,
            },
        };
        return new Border
        {
            BorderBrush = _chrome.Border,
            BorderThickness = new Thickness(2, 0, 0, 0),
            Padding = new Thickness(7, 0, 0, 0),
            Child = content,
        };
    }

    private UIElement RenderBanner(Block.Banner banner)
    {
        var stack = new StackPanel();
        foreach (var p in banner.Paragraphs)
        {
            stack.Children.Add(WrapText(p));
            stack.Children.Add(new Border { Height = 4 });
        }
        stack.Children.Add(RenderRow(banner.ControlsRow.Controls));
        return new Border
        {
            Background = _chrome.WarningBackground,
            BorderBrush = _chrome.WarningBorder,
            BorderThickness = new Thickness(3, 0, 0, 0),
            Padding = new Thickness(6),
            Child = stack,
        };
    }

    private UIElement RenderCodeCommand(Block.CodeCommand cmd)
    {
        var code = new TextBox
        {
            Text = cmd.Command,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = _chrome.Mono,
            FontSize = 11,
            Background = _chrome.CodeBackground,
            Foreground = _chrome.Foreground,
            BorderBrush = _chrome.Border,
            BorderThickness = new Thickness(1),
            Padding = new Thickness(5, 4, 5, 4),
            VerticalContentAlignment = VerticalAlignment.Center,
        };
        var grid = new Grid { Margin = new Thickness(0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(code, 0);
        var copy = RenderControl(cmd.Copy);
        Grid.SetColumn(copy, 1);
        grid.Children.Add(code);
        grid.Children.Add(copy);
        return grid;
    }

    private UIElement RenderRow(IReadOnlyList<DomainControl> controls)
    {
        if (controls.Count == 1 && controls[0].Emphasis == Emphasis.Link)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(RenderControl(controls[0]));
            return panel;
        }

        if (controls.Count == 2)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var a = RenderControl(controls[0]);
            var b = RenderControl(controls[1]);
            Grid.SetColumn(a, 0);
            Grid.SetColumn(b, 2);
            grid.Children.Add(a);
            grid.Children.Add(b);
            return grid;
        }

        return RenderControl(controls[0]);
    }

    private UIElement RenderFileRows(Block.FileRows files)
    {
        var stack = new StackPanel();
        foreach (var f in files.Rows)
            stack.Children.Add(FileRowButton(f));
        return stack;
    }

    private UIElement FileRowButton(FileRow f)
    {
        var btn = new Button
        {
            Content = new TextBlock
            {
                Text = f.Display,
                FontFamily = _chrome.Mono,
                FontSize = 12,
                TextWrapping = TextWrapping.NoWrap,
                TextTrimming = TextTrimming.CharacterEllipsis,
            },
            Style = _bareButton,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = f.LastOpened ? _chrome.RowSelected : Brushes.Transparent,
            BorderThickness = f.LastOpened ? new Thickness(2, 0, 0, 0) : new Thickness(0),
            BorderBrush = _chrome.LinkForeground,
            Padding = new Thickness(7, 3, 5, 3),
            Foreground = _chrome.Foreground,
            Cursor = Cursors.Hand,
            ToolTip = f.LastOpened ? $"Last opened: {f.Display}" : f.Display,
        };
        btn.Click += (_, _) => ActionRequested?.Invoke(ControlId.OpenChange.Wire(), f.Index, null);
        btn.MouseEnter += (_, _) => btn.Background = _chrome.RowHover;
        btn.MouseLeave += (_, _) =>
            btn.Background = f.LastOpened ? _chrome.RowSelected : Brushes.Transparent;
        return btn;
    }

    private UIElement RenderInventory(Block.InventoryRows inv)
    {
        var stack = new StackPanel();
        foreach (var r in inv.Rows)
        {
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = MonoLabel(r.Name);
            var badges = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var b in r.Badges) badges.Children.Add(Chip(b));
            if (r.Controls.Count == 0 && r.HelpTooltip is not null)
            {
                var help = Chip("?");
                help.ToolTip = r.HelpTooltip;
                badges.Children.Add(help);
            }
            Grid.SetColumn(name, 0);
            Grid.SetColumn(badges, 1);
            header.Children.Add(name);
            header.Children.Add(badges);
            stack.Children.Add(header);
            stack.Children.Add(MonoLabel(r.Meta, muted: true));
            if (r.Controls.Count > 0)
            {
                var actions = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Margin = new Thickness(0, 2, 0, 0),
                };
                foreach (var c in r.Controls)
                {
                    actions.Children.Add(RenderControl(c));
                    actions.Children.Add(new Border { Width = 4 });
                }
                stack.Children.Add(actions);
            }
            stack.Children.Add(new Border { Height = 6 });
        }
        return stack;
    }

    /// <summary>
    /// The draft block. Same shape as an inventory row — name, meta, actions — because it
    /// is the same kind of thing: a row of the empty state you act on. Product parity,
    /// not pixel parity: what has to match the other clients is the order, the labels and
    /// which controls a row offers.
    /// </summary>
    private UIElement RenderDrafts(Block.DraftRows block)
    {
        var stack = new StackPanel();
        foreach (var r in block.Rows)
        {
            // The progress rides the header instead of a line of its own: it is
            // a badge-sized fact about the branch, and one loose line per row
            // multiplied the height of the block for nothing.
            //
            // The Icon controls ride it too, right after the pair that names
            // their subject. Which half of the row a control lands in is read
            // off its emphasis and decided nowhere else: the layout already
            // says which of the four are glyphs.
            var glyphs = r.Controls.Where(c => c.Emphasis == Emphasis.Icon).ToList();
            var labelled = r.Controls.Where(c => c.Emphasis != Emphasis.Icon).ToList();
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = MonoLabel(r.Name);
            var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            right.Children.Add(Chip(r.Meta));
            foreach (var c in glyphs)
            {
                var glyph = RenderControl(c);
                glyph.Margin = new Thickness(2, 0, 0, 0);
                right.Children.Add(glyph);
            }
            Grid.SetColumn(name, 0);
            Grid.SetColumn(right, 1);
            header.Children.Add(name);
            header.Children.Add(right);
            stack.Children.Add(header);

            // A grid of even columns, not a panel that wraps: at sidebar width
            // two long labels do not fit on one line of free widths, and
            // wrapping them broke every row of the block in a different place —
            // none lined up with the one beside it. Even cells always do.
            var actions = new UniformGrid
            {
                Rows = 1,
                Columns = labelled.Count,
                Margin = new Thickness(0, 4, 0, 0),
            };
            foreach (var c in labelled)
            {
                var cell = RenderControl(c);
                cell.Margin = new Thickness(0, 0, 4, 4);
                actions.Children.Add(cell);
            }
            stack.Children.Add(actions);
            // Two draft rows in a row need more air between them than two
            // inventory ones: each is a header with glyphs plus its own button
            // pair, and without the gap the two read as a single pane.
            stack.Children.Add(new Border { Height = 10 });
        }
        return stack;
    }

    /// <summary>
    /// The authoring-guide rows. Same two-place shape as the draft rows — badge
    /// and glyphs in the header, the labelled control underneath — because they
    /// are the same kind of thing, and the reviewer should not have to learn a
    /// second row.
    ///
    /// Less air between rows than between drafts: there are exactly two, they
    /// belong together, and they sit inside a collapsed section rather than at
    /// the top of the empty state.
    /// </summary>
    private UIElement RenderGuides(Block.GuideRows block)
    {
        var stack = new StackPanel();
        foreach (var r in block.Rows)
        {
            var glyphs = r.Controls.Where(c => c.Emphasis == Emphasis.Icon).ToList();
            var labelled = r.Controls.Where(c => c.Emphasis != Emphasis.Icon).ToList();
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = MonoLabel(r.Name);
            var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            right.Children.Add(Chip(r.Badge));
            foreach (var c in glyphs)
            {
                var glyph = RenderControl(c);
                glyph.Margin = new Thickness(2, 0, 0, 0);
                right.Children.Add(glyph);
            }
            Grid.SetColumn(name, 0);
            Grid.SetColumn(right, 1);
            header.Children.Add(name);
            header.Children.Add(right);
            stack.Children.Add(header);

            var actions = new UniformGrid
            {
                Rows = 1,
                Columns = labelled.Count,
                Margin = new Thickness(0, 4, 0, 0),
            };
            foreach (var c in labelled)
            {
                var cell = RenderControl(c);
                cell.Margin = new Thickness(0, 0, 4, 4);
                actions.Children.Add(cell);
            }
            stack.Children.Add(actions);
            stack.Children.Add(new Border { Height = 6 });
        }
        return stack;
    }

    private UIElement RenderToolsSection(Block.ToolsSection section)
    {
        var open = _sectionOpen.GetValueOrDefault(section.Title, false);
        var stack = new StackPanel
        {
            Margin = new Thickness(0, 4, 0, 0),
        };
        var toggle = new Button
        {
            Content = (open ? "▼ " : "▶ ") + section.Title,
            Style = _bareButton,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = Brushes.Transparent,
            Foreground = _chrome.MutedForeground,
            FontWeight = FontWeights.SemiBold,
            FontSize = 11,
            Padding = new Thickness(0, 6, 0, 4),
            Cursor = Cursors.Hand,
        };
        var body = new StackPanel { Visibility = open ? Visibility.Visible : Visibility.Collapsed };
        foreach (var b in section.NestedBlocks)
        {
            body.Children.Add(RenderBlock(b));
            body.Children.Add(new Border { Height = 4 });
        }
        // Hover in the panel's own colors: the bare style has no trigger of its
        // own, so a section header without this reads as dead text.
        toggle.MouseEnter += (_, _) => toggle.Foreground = _chrome.Foreground;
        toggle.MouseLeave += (_, _) => toggle.Foreground = _chrome.MutedForeground;
        toggle.Click += (_, _) =>
        {
            _sectionOpen[section.Title] = !_sectionOpen.GetValueOrDefault(section.Title, false);
            // Re-render would need parent model; toggle local body for FR-034
            var now = _sectionOpen[section.Title];
            toggle.Content = (now ? "▼ " : "▶ ") + section.Title;
            body.Visibility = now ? Visibility.Visible : Visibility.Collapsed;
        };
        stack.Children.Add(new Border
        {
            BorderBrush = _chrome.Border,
            BorderThickness = new Thickness(0, 1, 0, 0),
            Child = toggle,
        });
        stack.Children.Add(body);
        return stack;
    }

    private UIElement RenderStderr(string text) =>
        new TextBox
        {
            Text = text,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = _chrome.Mono,
            FontSize = 11,
            Background = _chrome.CodeBackground,
            Foreground = _chrome.MutedForeground,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(6),
        };

    private UIElement RenderEmpty(Block.EmptyMessage em)
    {
        var stack = new StackPanel();
        stack.Children.Add(WrapText(em.Text));
        if (em.Control is not null)
        {
            stack.Children.Add(new Border { Height = 6 });
            stack.Children.Add(RenderControl(em.Control));
        }
        if (em.StderrText is not null)
        {
            stack.Children.Add(new Border { Height = 6 });
            stack.Children.Add(RenderStderr(em.StderrText));
        }
        return stack;
    }

    private FrameworkElement RenderTitleControl(DomainControl c)
    {
        var btn = new Button
        {
            Content = c.Label ?? c.AccessibleName,
            Style = _secondaryButton,
            Margin = new Thickness(0, 0, 4, 0),
            Padding = new Thickness(8, 3, 8, 3),
            IsEnabled = c.Enabled,
            FontSize = 11,
            ToolTip = c.Tooltip ?? c.AccessibleName,
        };
        btn.Click += (_, _) => ActionRequested?.Invoke(c.Id.Wire(), c.Index, c.SupportLinkId);
        return btn;
    }

    private FrameworkElement RenderControl(DomainControl c)
    {
        if (c.Emphasis == Emphasis.Icon)
        {
            // This host draws icon controls as text glyphs (no Image Catalog
            // outside the VSIX), so they stay in the BMP: an astral codepoint
            // is a tofu box in whatever font the theme hands us.
            var icon = c.Id == ControlId.Prev ? "◀"
                : c.Id == ControlId.OpenDraft ? "▤"
                : c.Id == ControlId.DiscardDraft ? "✕"
                : "▶";
            var b = new Button
            {
                Content = icon,
                Style = _secondaryButton,
                Width = 32,
                Height = 28,
                IsEnabled = c.Enabled,
                // The tooltip proper when the layout gave the control one: a
                // glyph whose hover only repeats its own name says nothing the
                // glyph did not, and the draft ones carry the command they run.
                ToolTip = c.Tooltip ?? c.AccessibleName,
            };
            b.Click += (_, _) => ActionRequested?.Invoke(c.Id.Wire(), c.Index, c.SupportLinkId);
            return b;
        }

        if (c.Emphasis == Emphasis.Link)
        {
            var link = new TextBlock
            {
                Text = c.Label ?? c.AccessibleName,
                Foreground = c.Enabled ? _chrome.LinkForeground : _chrome.MutedForeground,
                TextDecorations = TextDecorations.Underline,
                Cursor = c.Enabled ? Cursors.Hand : Cursors.Arrow,
                FontSize = 12,
            };
            if (c.Enabled)
            {
                link.MouseLeftButtonUp += (_, _) =>
                    ActionRequested?.Invoke(c.Id.Wire(), c.Index, c.SupportLinkId);
            }
            return link;
        }

        var btn = new Button
        {
            Content = c.Label ?? c.AccessibleName,
            Style = c.Emphasis == Emphasis.Primary ? _primaryButton : _secondaryButton,
            IsEnabled = c.Enabled,
            Padding = new Thickness(10, 5, 10, 5),
            FontSize = 12,
            ToolTip = c.Tooltip,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        if (c.Emphasis == Emphasis.Primary) btn.FontWeight = FontWeights.SemiBold;
        // What the button was drawn as, for whoever looks at the rendered tree
        // rather than at the layout: --verify reads the disabled pair off it.
        btn.Tag = c.Emphasis;
        // A control whose accessible name is not its label says so: "Open" on
        // its own repeats once per draft row and names none of them.
        if (c.AccessibleName != c.Label)
        {
            System.Windows.Automation.AutomationProperties.SetName(btn, c.AccessibleName);
        }

        btn.Click += (_, _) => ActionRequested?.Invoke(c.Id.Wire(), c.Index, c.SupportLinkId);
        return btn;
    }

    private TextBlock WrapText(string text, bool muted = false) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        FontSize = 12,
        FontFamily = _chrome.Ui,
        Foreground = muted ? _chrome.MutedForeground : _chrome.Foreground,
    };

    private TextBlock MonoLabel(string text, bool bold = false, bool muted = false, double marginLeft = 0) => new()
    {
        Text = text,
        FontFamily = _chrome.Mono,
        FontSize = 12,
        FontWeight = bold ? FontWeights.Bold : FontWeights.Normal,
        Foreground = muted ? _chrome.MutedForeground : _chrome.Foreground,
        Margin = new Thickness(marginLeft, 0, 0, 0),
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>
    /// A mark on an entry or an inventory row, in the extension's three weights:
    /// <c>key</c> is what the walkthrough author called essential and goes solid,
    /// in the badge pair, which is the one fill here whose contrast is fixed by
    /// the chrome rather than by the host; <c>uncovered</c> and the help mark are
    /// warnings of ours and go bare; everything else — <c>edits</c>,
    /// <c>current</c>, <c>orphan</c> — is a state and goes in outline. Which is
    /// which is read off the text, exactly as JetBrains and the extension read it
    /// off the class. The border is always drawn, transparent when there is no
    /// outline, so all three weights lay out to the same size.
    /// </summary>
    private Border Chip(string text)
    {
        var solid = text == "key";
        var bare = text is "uncovered" or "?";
        return new Border
        {
            Background = solid ? _chrome.BadgeBackground : Brushes.Transparent,
            BorderBrush = solid || bare ? Brushes.Transparent : _chrome.Border,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(4, 0, 4, 0),
            Margin = new Thickness(4, 0, 0, 0),
            Child = new TextBlock
            {
                Text = text,
                FontSize = 10,
                Foreground = solid
                    ? _chrome.BadgeForeground
                    : bare ? _chrome.MutedForeground : _chrome.Foreground,
                FontFamily = _chrome.Mono,
            },
        };
    }

    private Border SkeletonBar(double fraction, double height = 12) => new()
    {
        Background = _chrome.Skeleton,
        Height = height,
        Width = Math.Max(40, 160 * fraction),
        CornerRadius = new CornerRadius(2),
        HorizontalAlignment = HorizontalAlignment.Left,
        Margin = new Thickness(0, 2, 0, 2),
    };
}
