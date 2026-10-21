using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using GitReview.Domain;

namespace GitReview.VS.ToolWindows;

public sealed class CommentsComposer : Window
{
    private readonly ComboBox _destination = new() {SelectedIndex=-1,HorizontalAlignment=HorizontalAlignment.Stretch};
    private readonly ComboBox _scope = new() {HorizontalAlignment=HorizontalAlignment.Stretch};
    private readonly TextBox _text = new() {AcceptsReturn=true,TextWrapping=TextWrapping.Wrap,MinHeight=80,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalAlignment=HorizontalAlignment.Stretch};
    private readonly TextBlock _error = new() {TextWrapping=TextWrapping.Wrap};
    private readonly Button _save, _cancel;
    private bool _busy;
    public CommentsComposer(CommentCapture? capture, IReadOnlyList<string> destinations, Func<string,string,string,Task<string?>> submit)
    {
        _destination.ItemsSource=destinations.Select(kind=>kind=="local"?CommentsCopy.localDestination:CommentsCopy.sharedDestination).ToArray();
        _destination.SelectedIndex=destinations.Count==1?0:-1;
        Title=CommentsCopy.add;Width=640;Height=540;MinWidth=420;MinHeight=360;
        var scopes=capture is null?new[]{"general"}:capture.HasSelection?new[]{"selection","file","general"}:new[]{"file","general"};
        string ScopeLabel(string scope)=>scope=="general"?CommentsCopy.general:(scope=="selection"?CommentsCopy.selection:CommentsCopy.file)+" · "+capture!.Path+(scope=="selection"?":"+capture.RangeLabel:"")+" ("+(capture.Side=="base"?CommentsCopy.baseSide:CommentsCopy.headSide)+")";
        _scope.ItemsSource=scopes.Select(ScopeLabel).ToArray();_scope.SelectedIndex=0;
        var chrome=GitReviewDialogs.Chrome;
        GitReviewDialogs.OwnModeless(this);
        Background=chrome.Background;Foreground=chrome.Foreground;FontFamily=chrome.Ui;
        Resources=CommentsBrowser.WindowResources(chrome);
        Resources[SystemColors.WindowBrushKey]=chrome.CodeBackground;
        Resources[SystemColors.WindowTextBrushKey]=chrome.Foreground;
        Resources[SystemColors.ControlBrushKey]=chrome.CodeBackground;
        Resources[SystemColors.ControlTextBrushKey]=chrome.Foreground;
        Resources[SystemColors.HighlightBrushKey]=chrome.RowSelected;
        Resources[SystemColors.HighlightTextBrushKey]=chrome.Foreground;
        Resources.MergedDictionaries.Add(InputResources(chrome));
        foreach(var input in new System.Windows.Controls.Control[]{_text,_scope,_destination}){
            input.Background=chrome.CodeBackground;input.Foreground=chrome.Foreground;input.BorderBrush=chrome.Border;
            input.Padding=new Thickness(6,4,6,4);
        }
        _text.CaretBrush=chrome.Foreground;_error.Foreground=chrome.WarningBorder;
        System.Windows.Automation.AutomationProperties.SetName(_text,CommentsCopy.body);
        var grid=new Grid{Margin=new Thickness(16),Resources=Resources};
        // Context can scroll independently when a selection and its warning are
        // present. Reserve most of the client area for writing at the minimum size.
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        var contextRow=new RowDefinition{Height=new GridLength(1,GridUnitType.Star),MaxHeight=180};
        grid.RowDefinitions.Add(contextRow);
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(3,GridUnitType.Star),MinHeight=80});
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        var context=new StackPanel();
        var contextScroll=new ScrollViewer{Content=context,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Margin=new Thickness(0,0,0,8)};
        Grid.SetRow(contextScroll,1);grid.Children.Add(contextScroll);
        void Add(UIElement element)=>context.Children.Add(element);
        void Place(UIElement element,int row){Grid.SetRow(element,row);grid.Children.Add(element);}
        var scopeControls=new StackPanel();
        scopeControls.Children.Add(new TextBlock{Text=CommentsCopy.scope,Foreground=chrome.Foreground,Margin=new Thickness(0,0,0,4)});
        _scope.Margin=new Thickness(0,0,0,10);scopeControls.Children.Add(_scope);Place(scopeControls,0);
        var preview=new TextBox{IsReadOnly=true,TextWrapping=TextWrapping.Wrap,MaxHeight=100,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalAlignment=HorizontalAlignment.Stretch,Margin=new Thickness(0,0,0,10),Background=chrome.CodeBackground,Foreground=chrome.Foreground,BorderBrush=chrome.Border,Padding=new Thickness(6),FontFamily=chrome.Mono};
        Add(preview);
        void Context(){var selected=scopes[_scope.SelectedIndex]=="selection";preview.Visibility=selected?Visibility.Visible:Visibility.Collapsed;preview.Text=selected?capture!.Snippet:"";var visible=selected||capture?.Unversioned==true;contextScroll.Visibility=visible?Visibility.Visible:Visibility.Collapsed;contextRow.Height=visible?new GridLength(1,GridUnitType.Star):GridLength.Auto;}
        _scope.SelectionChanged+=(_,_)=>Context();Context();
        if(capture?.Unversioned==true)Add(new TextBlock{Text=CommentsCopy.unversioned,Foreground=chrome.MutedForeground,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,10)});
        var destination=new Grid{Visibility=destinations.Count>1?Visibility.Visible:Visibility.Collapsed,Margin=new Thickness(0,0,0,10)};
        destination.Children.Add(_destination);
        var placeholder=new TextBlock{Text=CommentsCopy.destination,IsHitTestVisible=false,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(6,0,28,0),Foreground=chrome.MutedForeground};
        destination.Children.Add(placeholder);Place(destination,2);
        System.Windows.Automation.AutomationProperties.SetName(_destination,CommentsCopy.destination);
        void Placeholder(){placeholder.Visibility=_destination.SelectedIndex<0&&!_destination.IsDropDownOpen?Visibility.Visible:Visibility.Collapsed;}
        _destination.DropDownOpened+=(_,_)=>Placeholder();_destination.DropDownClosed+=(_,_)=>Placeholder();
        _destination.SelectionChanged+=(_,_)=>Placeholder();
        Place(new Label{Content=CommentsCopy.body,Target=_text,Foreground=chrome.Foreground},3);
        Place(_text,4);
        Place(new ScrollViewer{Content=_error,MaxHeight=60,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled},5);
        var buttons=new StackPanel{Orientation=Orientation.Horizontal,Margin=new Thickness(0,10,0,0)};
        _save=new Button{Content=CommentsCopy.submit,Style=PanelButtons.Style(chrome,PanelButtonKind.Primary),IsEnabled=false,Margin=new Thickness(0,0,8,0),Padding=new Thickness(12,6,12,6),MinWidth=80,MinHeight=28};
        _cancel=new Button{Content=CommentsCopy.cancel,Style=PanelButtons.Style(chrome,PanelButtonKind.Secondary),Padding=new Thickness(12,6,12,6),MinWidth=80,MinHeight=28};
        buttons.Children.Add(_save);buttons.Children.Add(_cancel);Place(buttons,6);Content=grid;
        _destination.SelectionChanged+=(_,_)=>Update();_text.TextChanged+=(_,_)=>Update();
        _cancel.Click+=(_,_)=>{if(!_busy)Close();};
        Closing+=(_,e)=>{if(_busy)e.Cancel=true;};
        _save.Click+=async(_,_)=>{
            if(!_save.IsEnabled)return;_busy=true;_error.Text="";Update();
            try{var error=await submit(destinations[_destination.SelectedIndex],_text.Text,scopes[_scope.SelectedIndex]).ConfigureAwait(true);if(error is null){_busy=false;Close();}else _error.Text=error;}
            catch(Exception error){_error.Text=error.Message;}
            finally{_busy=false;Update();}
        };
        PreviewKeyDown+=(_,e)=>{if(e.Key==Key.Escape&&!_busy){e.Handled=true;Close();}else if(e.Key==Key.Enter&&(Keyboard.Modifiers&ModifierKeys.Control)!=0){e.Handled=true;if(_save.IsEnabled)_save.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));}};
        Loaded+=(_,_)=>_text.Focus();
    }
    private static ResourceDictionary InputResources(PanelChrome chrome)
    {
        // Native ComboBox templates contain OS colors which ignore the IDE theme.
        var resources=(ResourceDictionary)XamlReader.Parse(@"
<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Style TargetType='{x:Type ComboBoxItem}'>
    <Setter Property='Foreground' Value='{DynamicResource CommentInputForeground}'/>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ComboBoxItem'>
      <Border x:Name='Item' Background='{DynamicResource CommentInputBackground}' Padding='6,4'><ContentPresenter/></Border>
      <ControlTemplate.Triggers><Trigger Property='IsHighlighted' Value='True'><Setter TargetName='Item' Property='Background' Value='{DynamicResource CommentInputSelection}'/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType='{x:Type ComboBox}'>
    <Setter Property='MinHeight' Value='28'/>
    <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ComboBox'>
      <Grid>
        <Border Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1'>
          <ContentPresenter Margin='6,4,24,4' IsHitTestVisible='False' VerticalAlignment='Center' Content='{TemplateBinding SelectionBoxItem}' ContentTemplate='{TemplateBinding SelectionBoxItemTemplate}' TextElement.Foreground='{TemplateBinding Foreground}'/>
        </Border>
        <ToggleButton Focusable='False' IsChecked='{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}'>
          <ToggleButton.Template><ControlTemplate TargetType='ToggleButton'><Border Background='Transparent'><TextBlock Text='▾' Foreground='{DynamicResource CommentInputForeground}' HorizontalAlignment='Right' VerticalAlignment='Center' Margin='0,0,8,0'/></Border></ControlTemplate></ToggleButton.Template>
        </ToggleButton>
        <Popup x:Name='PART_Popup' IsOpen='{TemplateBinding IsDropDownOpen}' Placement='Bottom' AllowsTransparency='True' Focusable='False'>
          <Border Background='{DynamicResource CommentInputBackground}' BorderBrush='{DynamicResource CommentInputBorder}' BorderThickness='1' MinWidth='{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}'>
            <ScrollViewer MaxHeight='240' CanContentScroll='True' HorizontalScrollBarVisibility='Disabled' VerticalScrollBarVisibility='Auto'><ItemsPresenter KeyboardNavigation.DirectionalNavigation='Contained'/></ScrollViewer>
          </Border>
        </Popup>
      </Grid>
      <ControlTemplate.Triggers><Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='0.6'/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Setter.Value></Setter>
  </Style>
</ResourceDictionary>");
        resources["CommentInputBackground"]=chrome.CodeBackground;
        resources["CommentInputForeground"]=chrome.Foreground;
        resources["CommentInputBorder"]=chrome.Border;
        resources["CommentInputSelection"]=chrome.RowSelected;
        return resources;
    }
    private void Update(){_save.IsEnabled=!_busy&&_destination.SelectedIndex>=0&&!string.IsNullOrWhiteSpace(_text.Text);_save.Content=_busy?CommentsCopy.saving:CommentsCopy.submit;_cancel.IsEnabled=!_busy;_scope.IsEnabled=!_busy;_destination.IsEnabled=!_busy;_text.IsReadOnly=_busy;}
}
