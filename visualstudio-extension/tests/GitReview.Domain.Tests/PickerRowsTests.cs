using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The filter behind every picker. What is asserted here is not "it filters" but the two
/// things that silently return the wrong branch when they break: a row always means the
/// option it came from no matter what is filtered away, and the free-text row — the only
/// one with no option behind it — is the one selected while it is showing.
/// </summary>
public class PickerRowsTests
{
    private static readonly string[] Branches =
    {
        "main",
        "develop",
        "feature/checkout",
        "feature/cart",
        "release/2.0",
    };

    [Fact]
    public void an_empty_needle_keeps_every_option_in_order()
    {
        var rows = PickerRows.Rows(Branches, "", freeText: false);
        Assert.Equal(new[] { 0, 1, 2, 3, 4 }, rows);
    }

    [Fact]
    public void rows_carry_the_index_into_the_caller_list_not_the_visible_position()
    {
        var rows = PickerRows.Rows(Branches, "feature/", freeText: false);
        // Las dos feature/* son la 3ra y 4ta opcion, no la 1ra y 2da fila.
        Assert.Equal(new[] { 2, 3 }, rows);
    }

    [Fact]
    public void the_filter_is_case_insensitive_and_matches_anywhere()
    {
        Assert.Equal(new[] { 2 }, PickerRows.Rows(Branches, "CHECKOUT", freeText: false));
        Assert.Equal(new[] { 4 }, PickerRows.Rows(Branches, "2.0", freeText: false));
    }

    [Fact]
    public void a_needle_that_matches_nothing_leaves_no_rows()
    {
        Assert.Empty(PickerRows.Rows(Branches, "nope", freeText: false));
    }

    [Fact]
    public void without_free_text_a_typed_value_is_never_offered_as_a_row()
    {
        var rows = PickerRows.Rows(Branches, "v1.2.3", freeText: false);
        Assert.Empty(rows);
        Assert.DoesNotContain(PickerRows.Typed, rows);
    }

    [Fact]
    public void free_text_offers_the_typed_value_first_when_it_matches_no_option()
    {
        var rows = PickerRows.Rows(Branches, "v1.2.3", freeText: true);
        Assert.Equal(new[] { PickerRows.Typed }, rows);
    }

    [Fact]
    public void free_text_keeps_the_matches_behind_the_typed_row()
    {
        var rows = PickerRows.Rows(Branches, "feature", freeText: true);
        Assert.Equal(new[] { PickerRows.Typed, 2, 3 }, rows);
    }

    [Fact]
    public void free_text_does_not_duplicate_an_option_typed_in_full()
    {
        var rows = PickerRows.Rows(Branches, "main", freeText: true);
        Assert.Equal(new[] { 0 }, rows);
        Assert.DoesNotContain(PickerRows.Typed, rows);
    }

    [Fact]
    public void surrounding_whitespace_is_not_part_of_the_needle()
    {
        Assert.Equal(new[] { 0 }, PickerRows.Rows(Branches, "  main  ", freeText: true));
    }

    // -- selection ----------------------------------------------------------

    [Fact]
    public void with_no_rows_nothing_is_selected()
    {
        Assert.Equal(PickerRows.None, PickerRows.Selection(Array.Empty<int>(), keep: 2));
    }

    [Fact]
    public void the_previous_selection_survives_a_filter_that_still_shows_it()
    {
        var rows = PickerRows.Rows(Branches, "feature/", freeText: false);
        // La opcion 3 es feature/cart, que sigue visible: fila 1 de las dos que quedan.
        Assert.Equal(1, PickerRows.Selection(rows, keep: 3));
    }

    [Fact]
    public void a_previous_selection_that_got_filtered_away_falls_back_to_the_first_row()
    {
        var rows = PickerRows.Rows(Branches, "feature/", freeText: false);
        Assert.Equal(0, PickerRows.Selection(rows, keep: 0));
    }

    /// <summary>
    /// El caso que motiva todo: tipear un SHA con una rama seleccionada de antes y que
    /// aceptar mande la rama. La fila de texto libre gana la seleccion mientras esta.
    /// </summary>
    [Fact]
    public void the_typed_row_wins_the_selection_over_a_previous_pick()
    {
        var rows = PickerRows.Rows(Branches, "feature", freeText: true);
        Assert.Equal(PickerRows.Typed, rows[0]);
        Assert.Equal(0, PickerRows.Selection(rows, keep: 3));
    }

    [Fact]
    public void with_no_previous_pick_the_first_row_is_selected()
    {
        var rows = PickerRows.Rows(Branches, "", freeText: false);
        Assert.Equal(0, PickerRows.Selection(rows, keep: PickerRows.None));
    }
}
