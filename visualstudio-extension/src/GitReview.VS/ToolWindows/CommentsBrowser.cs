using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using WpfControl = System.Windows.Controls.Control;
using GitReview.Domain;

namespace GitReview.VS.ToolWindows;

public sealed class CommentsBrowser : Window
{
    public CommentsBrowser(IReadOnlyList<CommentPresentation> entries, Func<CommentPresentation, Task> open, Func<CommentPresentation, Task<IReadOnlyList<CommentPresentation>>>? remove = null)
    {
        Title = CommentsCopy.title; Width = 780; Height = 640; MinWidth = 420; MinHeight = 360;
        GitReviewDialogs.OwnModeless(this);
        var chrome = GitReviewDialogs.Chrome;
        Resources = WindowResources(chrome);
        Background = chrome.Background; Foreground = chrome.Foreground; FontFamily = chrome.Ui;
        var grid = new Grid { Margin = new Thickness(16) };
        foreach (var height in new[] { new GridLength(1, GridUnitType.Star), GridLength.Auto, new GridLength(2.3, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            grid.RowDefinitions.Add(new RowDefinition { Height = height });
        grid.RowDefinitions[0].MinHeight = 75; grid.RowDefinitions[2].MinHeight = 100;
        void Add(UIElement control, int row) { Grid.SetRow(control, row); grid.Children.Add(control); }
        var list = new ListBox { HorizontalContentAlignment = HorizontalAlignment.Stretch, Background = chrome.Background, Foreground = chrome.Foreground, BorderThickness = new Thickness(0) };
        ScrollViewer.SetHorizontalScrollBarVisibility(list, ScrollBarVisibility.Disabled);
        System.Windows.Automation.AutomationProperties.SetName(list, CommentsCopy.entries);
        var itemStyle = new Style(typeof(ListBoxItem));
        itemStyle.Setters.Add(new Setter(WpfControl.BackgroundProperty, Brushes.Transparent));
        itemStyle.Setters.Add(new Setter(WpfControl.ForegroundProperty, chrome.Foreground));
        itemStyle.Setters.Add(new Setter(WpfControl.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
        var template = new ControlTemplate(typeof(ListBoxItem));
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.PaddingProperty, new Thickness(10, 8, 10, 8));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Stretch);
        border.AppendChild(presenter); template.VisualTree = border;
        itemStyle.Setters.Add(new Setter(WpfControl.TemplateProperty, template));
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(WpfControl.BackgroundProperty, chrome.RowHover)); itemStyle.Triggers.Add(hover);
        var selected = new Trigger { Property = ListBoxItem.IsSelectedProperty, Value = true };
        selected.Setters.Add(new Setter(WpfControl.BackgroundProperty, chrome.RowSelected)); itemStyle.Triggers.Add(selected);
        list.ItemContainerStyle = itemStyle;
        void AddEntry(CommentPresentation entry) {
            var row = new StackPanel { ToolTip = entry.Label };
            row.Children.Add(new TextBlock { Text = entry.Label, TextTrimming = TextTrimming.CharacterEllipsis });
            row.Children.Add(new TextBlock { Text = entry.Preview, TextTrimming = TextTrimming.CharacterEllipsis, Opacity = .8, Margin = new Thickness(0,5,0,0) });
            list.Items.Add(new ListBoxItem { Content = row, Tag = entry });
        }
        foreach (var entry in entries) AddEntry(entry);
        Add(list, 0);
        Add(new GridSplitter { Height = 7, HorizontalAlignment = HorizontalAlignment.Stretch, Background = Brushes.Transparent, ResizeDirection = GridResizeDirection.Rows, ResizeBehavior = GridResizeBehavior.PreviousAndNext }, 1);
        var detail = new Grid();
        detail.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        detail.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        detail.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Add(detail, 2);
        void Detail(UIElement control, int row) { Grid.SetRow(control, row); detail.Children.Add(control); }
        // The detail consists of prose, with technical history available on demand.
        var warning = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = chrome.WarningBorder, Margin = new Thickness(0,8,0,8), Visibility = Visibility.Collapsed }; Detail(warning, 0);
        var version = new TextBox { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, Background = chrome.Background, Foreground = chrome.MutedForeground, BorderThickness = new Thickness(0), MaxHeight = 100, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var details = new Expander { Header = CommentsCopy.details, Content = version, Foreground = chrome.MutedForeground, Margin = new Thickness(0,4,0,8) }; Detail(details, 1);
        var body = new TextBox { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = chrome.Background, Foreground = chrome.Foreground, BorderThickness = new Thickness(0), Padding = new Thickness(4,8,4,8), FontFamily = chrome.Ui };
        System.Windows.Automation.AutomationProperties.SetName(body, CommentsCopy.body); Detail(body, 2);
        var error = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0,8,0,0) }; Add(error, 3);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0,12,0,0) }; Add(actions, 4);
        var button = new Button { Content = CommentsCopy.openDiff, Style = PanelButtons.Style(chrome, PanelButtonKind.Primary), Padding = new Thickness(12,6,12,6), MinWidth = 80, IsEnabled = entries.Count > 0 }; actions.Children.Add(button);
        var delete = new Button { Content = CommentsCopy.delete, Style = PanelButtons.Style(chrome, PanelButtonKind.Secondary), Padding = new Thickness(12,6,12,6), MinWidth = 72, Margin = new Thickness(8,0,0,0), Visibility = remove is null ? Visibility.Collapsed : Visibility.Visible };
        actions.Children.Insert(1, delete);
        var busy = false;
        void Controls() {
            var entry = (list.SelectedItem as ListBoxItem)?.Tag as CommentPresentation;
            button.Visibility = entry?.CanOpenDiff == true ? Visibility.Visible : Visibility.Collapsed;
            button.IsEnabled = !busy && entry?.CanOpenDiff == true;
            delete.IsEnabled = !busy && entry is not null;
            list.IsEnabled = !busy;
        }
        void DetailChanged() {
            var entry = (list.SelectedItem as ListBoxItem)?.Tag as CommentPresentation;
            Controls();
            version.Text = entry?.Version ?? ""; details.IsExpanded = false; details.Visibility = string.IsNullOrEmpty(entry?.Version) ? Visibility.Collapsed : Visibility.Visible;
            warning.Text = entry?.Warning ?? ""; warning.Visibility = string.IsNullOrEmpty(entry?.Warning) ? Visibility.Collapsed : Visibility.Visible;
            body.Text = entry?.Body ?? CommentsCopy.empty; body.ScrollToHome();
        }
        list.SelectionChanged += (_,_) => DetailChanged();
        button.Click += async (_,_) => {
            if (busy || list.SelectedItem is not ListBoxItem {Tag: CommentPresentation {CanOpenDiff: true} entry}) return;
            busy = true; Controls(); error.Text = "";
            try { await open(entry).ConfigureAwait(true); Close(); } catch (Exception exception) { error.Text = exception.Message; }
            finally { busy = false; Controls(); }
        };
        delete.Click += async (_,_) => {
            if (busy || remove is null || list.SelectedItem is not ListBoxItem {Tag: CommentPresentation entry}) return;
            busy = true; Controls();
            try {
                if (!GitReviewDialogs.Confirm(ControlId.DeleteCommentEntry, CommentsCopy.deleteEntryTitle, CommentsCopy.deleteEntryDetail, CommentsCopy.delete)) return;
                var index = list.SelectedIndex; error.Text = "";
                var next = await remove(entry).ConfigureAwait(true);
                list.Items.Clear();
                foreach (var item in next) AddEntry(item);
                if (next.Count > 0) list.SelectedIndex = Math.Min(index, next.Count - 1);
                DetailChanged();
            } catch (Exception exception) { error.Text = exception.Message; }
            finally { busy = false; Controls(); }
        };
        PreviewKeyDown += (_, args) => {
            if (args.Key == System.Windows.Input.Key.Escape && !busy) { args.Handled = true; Close(); }
        };
        Content = grid; if (entries.Count > 0) list.SelectedIndex = 0; else DetailChanged();
    }
    // Scope these templates to this window: stock WPF arrows and scroll tracks
    // otherwise use the Windows theme rather than the IDE's palette.
    internal static ResourceDictionary WindowResources(PanelChrome chrome)
    {
        var resources = (ResourceDictionary)System.Windows.Markup.XamlReader.Parse(@"
<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Style TargetType='{x:Type ScrollBar}'>
    <Setter Property='Width' Value='12'/>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='{x:Type ScrollBar}'>
      <Grid Background='{DynamicResource CommentScrollTrack}'>
        <Track x:Name='PART_Track' IsDirectionReversed='True'>
          <Track.DecreaseRepeatButton><RepeatButton Command='{x:Static ScrollBar.PageUpCommand}' Focusable='False'><RepeatButton.Template><ControlTemplate TargetType='RepeatButton'><Border Background='Transparent'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
          <Track.Thumb><Thumb MinHeight='20'><Thumb.Template><ControlTemplate TargetType='Thumb'><Border Margin='3,0' CornerRadius='3' Background='{DynamicResource CommentScrollThumb}'/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          <Track.IncreaseRepeatButton><RepeatButton Command='{x:Static ScrollBar.PageDownCommand}' Focusable='False'><RepeatButton.Template><ControlTemplate TargetType='RepeatButton'><Border Background='Transparent'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
        </Track>
      </Grid>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType='{x:Type Expander}'>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='{x:Type Expander}'>
      <StackPanel>
        <ToggleButton Content='{TemplateBinding Header}' Foreground='{TemplateBinding Foreground}' HorizontalContentAlignment='Left' IsChecked='{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}'>
          <ToggleButton.Template><ControlTemplate TargetType='ToggleButton'>
            <StackPanel Orientation='Horizontal' Background='Transparent'>
              <TextBlock x:Name='Arrow' Text='▸' Width='16'/><ContentPresenter/>
            </StackPanel>
            <ControlTemplate.Triggers><Trigger Property='IsChecked' Value='True'><Setter TargetName='Arrow' Property='Text' Value='▾'/></Trigger></ControlTemplate.Triggers>
          </ControlTemplate></ToggleButton.Template>
        </ToggleButton>
        <ContentPresenter x:Name='DetailsContent' Visibility='Collapsed'/>
      </StackPanel>
      <ControlTemplate.Triggers><Trigger Property='IsExpanded' Value='True'><Setter TargetName='DetailsContent' Property='Visibility' Value='Visible'/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
</ResourceDictionary>");
        resources["CommentScrollTrack"] = chrome.Background;
        resources["CommentScrollThumb"] = chrome.MutedForeground;
        return resources;
    }

}
