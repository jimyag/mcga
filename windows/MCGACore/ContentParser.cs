using System.Collections.Generic;

namespace MCGA.MCGACore
{
    public interface IContentParser
    {
        string Name { get; }
        ParserInfo? Info { get; }
        List<ParseResult> Parse(string content, string previousContent = "");
    }
}
