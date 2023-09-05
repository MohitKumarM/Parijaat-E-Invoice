tableextension 50507 UnitOfMeasure extends "Unit of Measure"
{
    fields
    {
        field(50100; "UOM For E Invoicing"; Code[8])
        {
            DataClassification = ToBeClassified;
        }
    }

    var
        myInt: Integer;
}