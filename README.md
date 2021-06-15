# md2tweets.pl

The Perl program `md2tweets.pl` is a companion to [`tumblelog`](https://github.com/john-bokma/tumblelog); it reads the input file of `tumbelog` and outputs tweets separated by '%', a format used by [`tweetfile`](https://github.com/john-bokma/tweetfile).

For example:

```
md2tweets --template-filename tweet.txt --blog-url https://plurrrr.com/ \
    plurrrr.md > tweets.txt
```
